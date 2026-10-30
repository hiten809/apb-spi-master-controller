# APB-SPI Master Controller

A synthesizable SPI master controller with an APB3-compatible programming interface, supporting all four SPI modes, programmable clock division, and independent transmit and receive FIFOs.

## Features

- APB3-compatible register interface
- SPI modes 0, 1, 2, and 3 (CPOL/CPHA)
- 8-bit, MSB-first serial transfers
- Programmable SPI clock divider
- One SPI slave-select output
- Independent TX and RX FIFOs, each with a depth of 4 bytes
- APB error responses for invalid accesses and FIFO boundary conditions
- RX FIFO full handling with transfer pause and recovery

## Register Map

| Register | Address | Access | Description |
|---|---:|---|---|
| CTRL | `0x00` | R/W | Enable, SPI mode, clock divider |
| STATUS | `0x04` | R | Busy and FIFO status flags |
| TXDATA | `0x08` | W | Transmit data |
| RXDATA | `0x0C` | R | Receive data |

### CTRL Register

- Bit 0: SPI enable
- Bits 2:1: SPI mode
- Bits 15:8: Clock divider

### STATUS Register

- Bit 0: Busy
- Bit 1: TX FIFO full
- Bit 2: TX FIFO empty
- Bit 3: RX FIFO full
- Bit 4: RX FIFO empty

## Verification

The project includes self-checking SystemVerilog testbenches and regression scripts.

| Verification area | Coverage |
|---|---|
| SPI modes | Modes 0–3 |
| Transfer patterns | 6 TX/RX patterns per mode |
| Multi-transfer operation | 4 consecutive transfers per mode |
| APB register and error checks | Register access, FIFO overflow, invalid accesses |
| RX FIFO full handling | Full detection, transfer pause, recovery, and data ordering |
| Static RTL checks | Verilator lint and Yosys structural checks |

The regression suite checks expected behavior using procedural testbench checks and `$fatal` on failures.

## Running the Regression

Requirements: Icarus Verilog, Verilator, and Yosys.

Run from this directory:

    chmod +x scripts/run_regression.sh
    ./scripts/run_regression.sh

The script runs lint, simulation tests, and Yosys checks. Results are written under results/.

## Repository Structure

    docs/spec.md
    rtl/apb_spi_master.sv
    tb/tb_apb_spi_master.sv
    tb/tb_rx_fifo_full.sv
    tb/tb_spi_multi_transfer.sv
    tb/tb_spi_transfer.sv
    scripts/run_regression.sh
    scripts/run_spi_patterns.sh
    results/full_regression.log
    results/verification_report.txt
    results/yosys_synthesis.log

## Implementation Notes and Limitations

- The design targets a single SPI slave.
- The APB interface implements the documented APB3-compatible subset.
- PREADY is asserted continuously.
- Verification is simulation-based; no formal or constrained-random verification is claimed.
- Yosys results are generic synthesis statistics, not physical area, timing, or power measurements.
- Reset during an active transfer and simultaneous FIFO boundary push/pop scenarios are not covered by the current regression suite.

## Design and Verification Artifacts

- [Design specification](docs/spec.md)
- [Verification report](results/verification_report.txt)
- [Full regression log](results/full_regression.log)
- [Yosys synthesis log](results/yosys_synthesis.log)
