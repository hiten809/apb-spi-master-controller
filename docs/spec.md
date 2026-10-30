# APB-Controlled SPI Master

## Objective
Implement and verify a synthesizable SPI master controlled through an
APB3-compatible register interface.

## Initial feature set
- APB3-compatible register interface
- SPI modes 0, 1, 2, and 3
- 8-bit transfers, MSB first
- One SPI slave
- Programmable clock divider
- Independent TX and RX FIFOs, depth 4
- Self-checking SystemVerilog testbench
- Behavioral SPI slave model
- Directed tests, basic assertions/checks, and coverage counters
- Verilator lint and Yosys synthesis report

## Register map

| Offset | Register | Access | Description |
|--------|----------|--------|-------------|
| 0x00 | CTRL   | R/W | Bit 0: enable; bits 2:1: SPI mode; bits 15:8: clock divider |
| 0x04 | STATUS | R | Bit 0: busy; bit 1: TX full; bit 2: TX empty; bit 3: RX full; bit 4: RX empty |
| 0x08 | TXDATA | W | Write the low 8 bits to enqueue a byte |
| 0x0C | RXDATA | R | Read the next received byte from the RX FIFO |

## Design conventions
- Reset is active-low and synchronous to PCLK.
- APB transfers complete when PSEL, PENABLE, and PREADY are all high.
- FIFO depth is 4 bytes.
- Invalid register accesses assert PSLVERR.
- The implementation and verification results must be reported honestly;
  unimplemented features must not be claimed as complete.
