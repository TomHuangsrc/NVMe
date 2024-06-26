#include <unistd.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <errno.h>
#include <spdlog/spdlog.h>
#include <spdlog/stopwatch.h>
#include <stdlib.h>

using namespace spdlog;

#define BITTWARE_SOC_DEV "/dev/xdma0_user"
#define SCRATCH_REG   0x0000

void *soc_addr = NULL;

int open_fpga(const char *dev) {
  int fd = 0;
  fd = open(dev, O_RDWR);
  if (fd < 0) info("failed to open FPGA with errno {}", errno);
  else info("success to open FPGA. fd : {}", fd);
  return fd;
}

void* Mmap(int fd) {
  void *addr = mmap(NULL, 64*1024, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  if (addr == NULL) info("failed to mmap with errno {}", errno);
  else info("success to mmap FPGA. addr : {}", addr);
  return addr;
}

uint32_t write_csr(void *fpga_addr, uint32_t wrdata, uint32_t offset) {
  volatile uint32_t *w = (uint32_t*)((size_t)fpga_addr + offset);
  *w = wrdata;
	return *w;
}

uint32_t read_csr(void *fpga_addr, uint32_t offset) {
  uint32_t rddata = *(uint32_t*)((size_t)fpga_addr + offset);
  return rddata;
}

void sw_reset(){
	info("SW Reset!");
	write_csr(soc_addr, 1, 0x04);
  sleep(1);
	write_csr(soc_addr, 0, 0x04);
}


int main(int argc, char *argv[]){
	spdlog::set_pattern("%^[%l]%$  %v");
  int soc_fd;

  // Open Bittware 250 SOC + mmap 64KB
  soc_fd = open_fpga(BITTWARE_SOC_DEV);
  soc_addr = Mmap(soc_fd);
 
  // Reset modules on FPGA
	sw_reset();	

  // CSR Test
  write_csr(soc_addr, 0x1234567a, 0x0);
  info("{:08X}", read_csr(soc_addr, 0x0));
  
  // TX Test
  write_csr(soc_addr, 0x1, 0x10); // Start Tx
  write_csr(soc_addr, 0x1, 0x14); // Finish Tx

  return 0;
}
