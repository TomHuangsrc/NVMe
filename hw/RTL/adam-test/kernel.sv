module kernel #(
  parameter HOST_ADDR_WIDTH = 32,
  parameter HOST_DATA_WIDTH = 32,
  parameter HP_ADDR_WIDTH = 48,
  parameter HP_DATA_WIDTH = 128
) (
  input logic clk,
  input logic rstn,
  output logic driver_rstn,

  // AXIL slave
  input  logic [HOST_ADDR_WIDTH-1:0]   host_awaddr,
  input  logic [HOST_DATA_WIDTH-1:0]   host_wdata,
  input  logic [HOST_DATA_WIDTH/8-1:0] host_wstrb,
  input  logic [HOST_ADDR_WIDTH-1:0]   host_araddr,
  output logic [HOST_DATA_WIDTH-1:0]   host_rdata,
  input  logic       host_awvalid,
  output logic       host_awready,
  input  logic       host_wvalid,
  output logic       host_wready,
  output logic [1:0] host_bresp,
  output logic       host_bvalid,
  input  logic       host_bready,
  input  logic       host_arvalid,
  output logic       host_arready,
  output logic [1:0] host_rresp,
  output logic       host_rvalid,
  input  logic       host_rready,

  // AXIB master
  output logic [HP_ADDR_WIDTH-1:0]   hp_awaddr,
  output logic [HP_DATA_WIDTH-1:0]   hp_wdata,
  output logic [HP_DATA_WIDTH/8-1:0] hp_wstrb,
  output logic [HP_ADDR_WIDTH-1:0]   hp_araddr,
  input  logic [HP_DATA_WIDTH-1:0]   hp_rdata,
  output logic [7:0] hp_awlen,
  output logic [2:0] hp_awsize,
  output logic [1:0] hp_awburst,
  output logic       hp_awvalid,
  input  logic       hp_awready,
  output logic       hp_wlast,
  output logic       hp_wvalid,
  input  logic       hp_wready,
  input  logic [1:0] hp_bresp,
  input  logic       hp_bvalid,
  output logic       hp_bready,
  output logic [7:0] hp_arlen,
  output logic [2:0] hp_arsize,
  output logic [1:0] hp_arburst,
  output logic       hp_arvalid,
  input  logic       hp_arready,
  input  logic [1:0] hp_rresp,
  input  logic       hp_rlast,
  input  logic       hp_rvalid,
  output logic       hp_rready
);

// Register map
// 0x00 WO kernel start trigger
// 0x04 RO kernel state (0=idle, 1=running, 2=done)
// 0x08 WO reset kernel state to idle
// 0x0c RW driver reset (0=reset, 1=normal)
// 0x10 RW start address (low)
// 0x14 RW start address (high)
// 0x18 RW end address (low)
// 0x1c RW end address (high)
// 0x20 RW start value (DW0)
// 0x24 RW start value (DW1)
// 0x28 RW start value (DW2)
// 0x2c RW start value (DW3)
// 0x30 RW stride (DW0)
// 0x34 RW stride (DW1)
// 0x38 RW stride (DW2)
// 0x3c RW stride (DW3)
// 0x40 RW benchmode (write=0, read=1)
// 0x44 RO checksum (after read)

typedef enum logic [1:0] {
  KERNEL_STATE_IDLE,
  KERNEL_STATE_RUNNING,
  KERNEL_STATE_DONE
} kernel_state_t;

// regs R/W by host
logic [63:0] start_addr;
logic [63:0] end_addr;
logic [127:0] start_value;
logic [127:0] value_stride;
logic benchmode;
logic [31:0] checksum;
logic driver_rstn_sw;

kernel_state_t kernel_state;
logic [HP_ADDR_WIDTH-1:0] cur_addr;
logic [HP_ADDR_WIDTH-1:0] cur_value_addr;
logic [HP_DATA_WIDTH-1:0] cur_value;

always_ff @(posedge clk, negedge rstn) begin
  if (~rstn) begin
    host_bvalid <= 0;
    host_rvalid <= 0;
    kernel_state <= KERNEL_STATE_IDLE;
    driver_rstn <= 0;
    driver_rstn_sw <= 1;
  end else begin
    host_bvalid <= 0;
    host_rvalid <= 0;
    driver_rstn <= driver_rstn_sw;
    if (host_awvalid & host_wvalid) begin
      host_bvalid <= 1;
      if          (host_awaddr == 'h00) begin
        kernel_state <= KERNEL_STATE_RUNNING;
        cur_addr <= start_addr;
        cur_value_addr <= start_addr;
        cur_value <= start_value;
        checksum <= 0;
      end else if (host_awaddr == 'h08) begin
        kernel_state <= KERNEL_STATE_IDLE;
      end else if (host_awaddr == 'h0c) begin
        driver_rstn_sw <= host_wdata;
      end else if (host_awaddr == 'h10) begin
        start_addr[31:0] <= host_wdata;
      end else if (host_awaddr == 'h14) begin
        start_addr[63:32] <= host_wdata;
      end else if (host_awaddr == 'h18) begin
        end_addr[31:0] <= host_wdata;
      end else if (host_awaddr == 'h1c) begin
        end_addr[63:32] <= host_wdata;
      end else if (host_awaddr == 'h20) begin
        start_value[31:0] <= host_wdata;
      end else if (host_awaddr == 'h24) begin
        start_value[63:32] <= host_wdata;
      end else if (host_awaddr == 'h28) begin
        start_value[95:64] <= host_wdata;
      end else if (host_awaddr == 'h2c) begin
        start_value[127:96] <= host_wdata;
      end else if (host_awaddr == 'h30) begin
        value_stride[31:0] <= host_wdata;
      end else if (host_awaddr == 'h34) begin
        value_stride[63:32] <= host_wdata;
      end else if (host_awaddr == 'h38) begin
        value_stride[95:64] <= host_wdata;
      end else if (host_awaddr == 'h3c) begin
        value_stride[127:96] <= host_wdata;
      end else if (host_awaddr == 'h40) begin
        benchmode <= host_wdata;
      end
    end
    if (host_arvalid) begin
      host_rvalid <= 1;
      if          (host_araddr == 'h04) begin
        host_rdata <= kernel_state;
      end else if (host_araddr == 'h0c) begin
        host_rdata <= driver_rstn_sw;
      end else if (host_araddr == 'h10) begin
        host_rdata <= start_addr[0 +: 32];
      end else if (host_araddr == 'h14) begin
        host_rdata <= start_addr[32 +: 32];
      end else if (host_araddr == 'h18) begin
        host_rdata <= end_addr[0 +: 32];
      end else if (host_araddr == 'h1c) begin
        host_rdata <= end_addr[32 +: 32];
      end else if (host_araddr == 'h20) begin
        host_rdata <= start_value[0 +: 32];
      end else if (host_araddr == 'h24) begin
        host_rdata <= start_value[32 +: 32];
      end else if (host_araddr == 'h28) begin
        host_rdata <= start_value[64 +: 32];
      end else if (host_araddr == 'h2c) begin
        host_rdata <= start_value[96 +: 32];
      end else if (host_araddr == 'h30) begin
        host_rdata <= value_stride[0 +: 32];
      end else if (host_araddr == 'h34) begin
        host_rdata <= value_stride[32 +: 32];
      end else if (host_araddr == 'h38) begin
        host_rdata <= value_stride[64 +: 32];
      end else if (host_araddr == 'h3c) begin
        host_rdata <= value_stride[96 +: 32];
      end else if (host_araddr == 'h40) begin
        host_rdata <= benchmode;
      end else if (host_araddr == 'h44) begin
        host_rdata <= checksum;
      end
    end
    if (kernel_state == KERNEL_STATE_RUNNING) begin
      if (benchmode == 0) begin // WRITE
        if (~hp_awvalid & ~hp_wvalid) begin
          kernel_state <= KERNEL_STATE_DONE;
        end
        if (hp_awvalid & hp_awready) begin
          cur_addr <= cur_addr + 4096; // 4KB stride
        end
        if (hp_wvalid & hp_wready) begin
          cur_value_addr <= cur_value_addr + 16; // 16B per beat
          cur_value[0 +: 32] <= cur_value[0 +: 32] + value_stride[0 +: 32];
          cur_value[32 +: 32] <= cur_value[32 +: 32] + value_stride[32 +: 32];
          cur_value[64 +: 32] <= cur_value[64 +: 32] + value_stride[64 +: 32];
          cur_value[96 +: 32] <= cur_value[96 +: 32] + value_stride[96 +: 32];
        end
      end
    end
  end
end

endmodule