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

The project includes self-checking SystemVerilog testbenches and a repeatable regression script.

| Verification area | Coverage |
|---|---|
| SPI transfers | Modes 0–3 |
| Transfer patterns | 6 TX/RX patterns per mode |
| Multi-transfer operation | 4 consecutive transfers per mode |
| APB register and error checks | Register access, FIFO overflow, invalid accesses |
| RX FIFO full handling | Full detection, transfer pause, recovery, and data ordering |
| Static RTL checks | Verilator lint and Yosys structural checks |

Latest regression results:

- 4/4 SPI single-transfer mode tests passed.
- 4/4 multi-transfer mode tests passed.
- APB register, FIFO overflow, and error checks passed.
- 4/4 RX FIFO full/pause/recovery mode tests passed.
- APB coverage: 5/5 writes, 4/4 reads, and 5/5 expected errors.

The testbenches use procedural checks and `$fatal` on failures.

## Running the Regression

### Requirements

- Icarus Verilog
- Verilator
- Yosys
- Graphviz (`dot`) for schematic generation

Run from the repository root:

```bash
chmod +x scripts/run_regression.sh
./scripts/run_regression.sh
.
├── docs/
│   └── spec.md
├── rtl/
│   └── apb_spi_master.sv
├── tb/
│   ├── tb_apb_spi_master.sv
│   ├── tb_rx_fifo_full.sv
│   ├── tb_spi_multi_transfer.sv
│   └── tb_spi_transfer.sv
├── scripts/
│   ├── run_regression.sh
│   └── run_spi_patterns.sh
└── apb-spi-results/
    ├── schematic/
    │   ├── apb_spi_master.svg
    │   └── apb_spi_master.dot
    ├── waveforms/
    │   ├── apb_registers.vcd
    │   ├── spi_mode0.vcd
    │   ├── spi_mode1.vcd
    │   ├── spi_mode2.vcd
    │   ├── spi_mode3.vcd
    │   ├── spi_multi_mode0.vcd
    │   ├── spi_multi_mode1.vcd
    │   ├── spi_multi_mode2.vcd
    │   ├── spi_multi_mode3.vcd
    │   ├── rx_fifo_full_mode0.vcd
    │   ├── rx_fifo_full_mode1.vcd
    │   ├── rx_fifo_full_mode2.vcd
    │   └── rx_fifo_full_mode3.vcd
    ├── verification_report.txt
    └── yosys_synthesis.log
q
EFO
