#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "========== VERILATOR LINT =========="
verilator --lint-only --Wall --top-module apb_spi_master \
  rtl/apb_spi_master.sv

echo "========== SPI MODES 0-3 =========="
for mode in 0 1 2 3; do
  echo "--- SPI MODE ${mode} ---"
  iverilog -g2012 -Wall -s tb_spi_transfer \
    -Ptb_spi_transfer.SPI_MODE="${mode}" \
    -o "/tmp/tb_spi_mode${mode}" \
    rtl/apb_spi_master.sv tb/tb_spi_transfer.sv
  vvp "/tmp/tb_spi_mode${mode}"
done

echo "========== MULTI-TRANSFER SPI MODES 0-3 =========="
for mode in 0 1 2 3; do
  echo "--- MULTI-TRANSFER SPI MODE ${mode} ---"
  iverilog -g2012 -Wall -s tb_spi_multi_transfer \
    -Ptb_spi_multi_transfer.SPI_MODE="${mode}" \
    -o "/tmp/tb_spi_multi_mode${mode}" \
    rtl/apb_spi_master.sv tb/tb_spi_multi_transfer.sv
  vvp "/tmp/tb_spi_multi_mode${mode}"
done

echo "========== APB / FIFO REGRESSION =========="
iverilog -g2012 -Wall -s tb_apb_spi_master \
  -o /tmp/tb_apb_spi_master \
  rtl/apb_spi_master.sv tb/tb_apb_spi_master.sv
vvp /tmp/tb_apb_spi_master

echo "========== RX FIFO FULL / PAUSE / RECOVERY =========="
for mode in 0 1 2 3; do
  echo "--- RX FIFO FULL TEST: SPI MODE ${mode} ---"
  iverilog -g2012 -Wall -s tb_rx_fifo_full \
    -Ptb_rx_fifo_full.SPI_MODE="${mode}" \
    -o "/tmp/tb_rx_fifo_full_mode${mode}" \
    rtl/apb_spi_master.sv tb/tb_rx_fifo_full.sv
  vvp "/tmp/tb_rx_fifo_full_mode${mode}"
done

echo "========== YOSYS CHECK AND STATISTICS =========="
yosys -p "read_verilog -sv rtl/apb_spi_master.sv; hierarchy -top apb_spi_master; proc; opt; check; stat" \
  | tee results/yosys_synthesis.log

echo "========== ALL REGRESSION CHECKS COMPLETED =========="
