#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

patterns=(
  "3C A5"
  "96 5A"
  "00 FF"
  "FF 00"
  "AA 55"
  "55 AA"
)

for mode in 0 1 2 3; do
  for pair in "${patterns[@]}"; do
    read -r tx rx <<< "$pair"
    echo "========== MODE $mode TX=$tx RX=$rx =========="

    iverilog -g2012 -Wall -s tb_spi_transfer \
      -Ptb_spi_transfer.SPI_MODE="$mode" \
      -Ptb_spi_transfer.TX_DATA="8'h$tx" \
      -Ptb_spi_transfer.SLAVE_RESPONSE="8'h$rx" \
      -o "/tmp/tb_spi_pattern_${mode}_${tx}_${rx}" \
      rtl/apb_spi_master.sv tb/tb_spi_transfer.sv

    vvp "/tmp/tb_spi_pattern_${mode}_${tx}_${rx}" \
      | grep -E 'TX verified|Received byte|PASS:|FATAL|ERROR'
  done
done

echo "PASS: all SPI mode/pattern combinations completed"
