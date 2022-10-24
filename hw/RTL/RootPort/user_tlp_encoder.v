
(* DowngradeIPIdentifiedWarnings = "yes" *)
module user_tlp_encoder #(
    parameter         AXI4_RQ_TUSER_WIDTH = 62,
    parameter         AXI4_RC_TUSER_WIDTH = 75,
    parameter [15:0]  REQUESTER_ID        = 16'h10EE,
    parameter         C_DATA_WIDTH        = 64,
    parameter         KEEP_WIDTH          = C_DATA_WIDTH / 32
  ) (
    input wire                user_clk,
    input wire                reset,

    // Tx - AXI-S Requester Request Interface
    input                         s_axis_rq_tready,
    output reg [C_DATA_WIDTH-1:0] s_axis_rq_tdata,
    output reg [KEEP_WIDTH-1:0]   s_axis_rq_tkeep,
    output reg [AXI4_RQ_TUSER_WIDTH-1:0]             s_axis_rq_tuser,
    output reg                    s_axis_rq_tlast,
    output reg                    s_axis_rq_tvalid,

    // Controller interface
    input wire [2:0]          tx_type,  
    input wire [7:0]          tx_tag,
    input wire [63:0]         tx_addr,
    input wire [31:0]         tx_data,
    input wire                tx_start,
    output reg                tx_done
  );

  // TLP type encoding for tx_type
  localparam [2:0] TYPE_MEMRD32 = 3'b000;
  localparam [2:0] TYPE_MEMWR32 = 3'b001;
  localparam [2:0] TYPE_MEMRD64 = 3'b010;
  localparam [2:0] TYPE_MEMWR64 = 3'b011;

  // State encoding
  localparam [1:0] ST_IDLE   = 2'd0;
  localparam [1:0] ST_CYC1   = 2'd1;
  localparam [1:0] ST_CYC2   = 2'd2;
  localparam [1:0] ST_CYC3   = 2'd3;

  // State variable
  reg [1:0]   pkt_state;

  // Registers to store format and type bits of the TLP header
  reg [2:0]   pkt_attr;
  reg [3:0]   pkt_type;


  always @(posedge user_clk) begin
    if (reset) begin
      pkt_state     <= ST_IDLE;
      tx_done       <= 1'b0;
    end else begin
      case (pkt_state)
        ST_IDLE: begin
          // Waiting for input from Controller module
          tx_done        <= 1'b0;
          if (tx_start) begin
            pkt_state    <= ST_CYC1;
          end
        end // ST_IDLE

        ST_CYC1: begin : beat_1
          // First Double-Quad-word - wait for data to be accepted by core
          if (s_axis_rq_tready) begin
            if ((tx_type == TYPE_MEMWR64) || (tx_type == TYPE_MEMWR32)) begin
              pkt_state    <= ST_CYC2;
            end else begin
              pkt_state  <= ST_IDLE;
              tx_done    <= 1'b1;
            end
          end
        end // ST_CYC1

        ST_CYC2: begin : beat_2
          // Second Quad-word - wait for data to be accepted by core
          if (s_axis_rq_tready) begin
            pkt_state  <= ST_IDLE;
            tx_done    <= 1'b1;
          end
        end // ST_CYC2

        default: begin
          pkt_state      <= ST_IDLE;
        end // default case
      endcase
    end
  end

  // Compute Format and Type fields from type of TLP requested
  always @(posedge user_clk) begin
    if (reset) begin
      pkt_attr     <= 3'b000;
      pkt_type     <= 4'b0000;
    end else begin
      case (tx_type)
        TYPE_MEMRD32: begin
          pkt_attr <= 3'b000;
          pkt_type <= 4'b0000;
        end
        TYPE_MEMWR32: begin
          pkt_attr <= 3'b010;
          pkt_type <= 4'b0001;
        end
        TYPE_MEMRD64: begin
          pkt_attr <= 3'b000;
          pkt_type <= 4'b0000;
        end
        TYPE_MEMWR64: begin
          pkt_attr <= 3'b010;
          pkt_type <= 4'b0001;
        end
        default: begin
          pkt_attr <= 3'b000;
          pkt_type <= 4'b0000;
        end
      endcase
    end
  end

  // Packet generation output
  always @* begin
    case (pkt_state)
      ST_IDLE: begin
        s_axis_rq_tlast  = 1'b0;
        s_axis_rq_tuser  = {AXI4_RQ_TUSER_WIDTH{1'b0}};
        s_axis_rq_tdata  = {C_DATA_WIDTH{1'b0}};
        s_axis_rq_tkeep  = {KEEP_WIDTH{1'b0}};
        s_axis_rq_tvalid = 1'b0;
      end // ST_IDLE

      ST_CYC1: begin
        // First 2 QW's (4 DW's) of TLP

        s_axis_rq_tlast  = ((tx_type == TYPE_MEMWR64) ||(tx_type == TYPE_MEMWR32)) ? 1'b0 : 1'b1;
        s_axis_rq_tuser  = {32'b0,
                            
                            4'b1010,      // Seq Number
                            8'h00,        // TPH Steering Tag
                            1'b0,         // TPH indirect Tag Enable
                            2'b0,         // TPH Type
                            1'b0,         // TPH Present
                            1'b0,         // Discontinue
                            3'b000,       // Byte Lane number in case of Address Aligned mode
                            4'b0000,      //last_dw_be_,    // Last BE of the Read Data
                            4'b1111};     //first_dw_be_ }; // First BE of the Read Data

        s_axis_rq_tdata  = {1'b0,
                            pkt_attr,                                    // Attr
                            3'b0,                                        // TC
                            1'b0,                                        // RID Enable
                            REQUESTER_ID, //16'b0,                       // Completer ID
                            tx_tag,                                      // Tag
                            16'h00AF,//REQUESTER_ID,                     // Requester ID
                            1'b0,                                        // Poisoned Req
                            pkt_type,                                    // Type
                            11'd1,                                       // Length
                            {32'b0, tx_addr[31:2], 2'b00}                // 32-bit address
                            };
        s_axis_rq_tkeep  = {KEEP_WIDTH{1'b1}};
        s_axis_rq_tvalid = 1'b1;
      end // ST_CYC1

      ST_CYC2: begin
        // Second 2 QW's of TLP (64-bit MWR only)
        s_axis_rq_tdata[31:0]   = tx_data;
        s_axis_rq_tdata[63:32]  = 32'h00000000;
        s_axis_rq_tdata[95:64]  = 32'h00000000;
        s_axis_rq_tdata[127:96] = 32'h00000000;
        s_axis_rq_tuser  = {AXI4_RQ_TUSER_WIDTH{1'b0}};
        s_axis_rq_tkeep  = 4'b0001;
        s_axis_rq_tvalid = 1'b1;
        s_axis_rq_tlast  = 1'b1;
      end // ST_CYC2

      default: begin
        s_axis_rq_tlast  = 1'b0;
        s_axis_rq_tuser  = {AXI4_RQ_TUSER_WIDTH{1'b0}};
        s_axis_rq_tdata  = {C_DATA_WIDTH{1'b0}};
        s_axis_rq_tkeep  = {KEEP_WIDTH{1'b0}};
        s_axis_rq_tvalid = 1'b0;
      end // default case
    endcase
  end

endmodule 