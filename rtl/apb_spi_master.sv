`timescale 1ns/1ps

module apb_spi_master #(
    parameter integer FIFO_DEPTH = 4
) (
    input  logic        PCLK,
    input  logic        PRESETn,
    input  logic        PSEL,
    input  logic        PENABLE,
    input  logic        PWRITE,
    input  logic [31:0] PADDR,
    input  logic [31:0] PWDATA,
    output logic [31:0] PRDATA,
    output logic        PREADY,
    output logic        PSLVERR,

    output logic        SCLK,
    output logic        MOSI,
    input  logic        MISO,
    output logic        CS_n
);

    localparam logic [31:0] ADDR_CTRL   = 32'h0000_0000;
    localparam logic [31:0] ADDR_STATUS = 32'h0000_0004;
    localparam logic [31:0] ADDR_TXDATA = 32'h0000_0008;
    localparam logic [31:0] ADDR_RXDATA = 32'h0000_000C;

    localparam integer PTR_WIDTH =
        (FIFO_DEPTH <= 1) ? 1 : $clog2(FIFO_DEPTH);
    localparam integer COUNT_WIDTH = $clog2(FIFO_DEPTH + 1);

    logic [31:0] ctrl_reg;
    logic [7:0] tx_fifo [0:FIFO_DEPTH-1];
    logic [7:0] rx_fifo [0:FIFO_DEPTH-1];

    logic [PTR_WIDTH-1:0] tx_wr_ptr, tx_rd_ptr;
    logic [PTR_WIDTH-1:0] rx_wr_ptr, rx_rd_ptr;
    logic [COUNT_WIDTH-1:0] tx_count, rx_count;

    logic busy;
    logic [6:0] tx_shift;
    logic [7:0] rx_shift;
    logic [3:0] sample_count;
    logic [7:0] divider_count;
    logic [1:0] spi_mode;
    logic leading_edge;

    wire cpol = spi_mode[1];
    wire cpha = spi_mode[0];
    wire [7:0] clk_div = ctrl_reg[15:8];

    wire apb_access = PSEL && PENABLE;
    wire apb_write  = apb_access && PWRITE;
    wire apb_read   = apb_access && !PWRITE;

    wire tx_empty = (tx_count == 0);
    wire tx_full  = (tx_count == COUNT_WIDTH'(FIFO_DEPTH));
    wire rx_empty = (rx_count == 0);
    wire rx_full  = (rx_count == COUNT_WIDTH'(FIFO_DEPTH));

    wire tx_push = apb_write && (PADDR == ADDR_TXDATA)
                   && !tx_full;
    wire rx_pop = apb_read && (PADDR == ADDR_RXDATA)
                  && !rx_empty;

    logic tx_start;
    logic rx_commit;
    logic [7:0] rx_commit_data;

    function automatic [PTR_WIDTH-1:0] ptr_next(
        input [PTR_WIDTH-1:0] ptr
    );
        if (ptr == PTR_WIDTH'(FIFO_DEPTH-1))
            ptr_next = '0;
        else
            ptr_next = ptr + 1'b1;
    endfunction

    always_comb begin
        PRDATA = 32'h0;
        PREADY = 1'b1;
        PSLVERR = 1'b0;

        if (apb_access) begin
            case (PADDR)
                ADDR_CTRL: begin
                    if (!PWRITE)
                        PRDATA = ctrl_reg;
                end

                ADDR_STATUS: begin
                    if (PWRITE) begin
                        PSLVERR = 1'b1;
                    end else begin
                        PRDATA[0] = busy;
                        PRDATA[1] = tx_full;
                        PRDATA[2] = tx_empty;
                        PRDATA[3] = rx_full;
                        PRDATA[4] = rx_empty;
                    end
                end

                ADDR_TXDATA: begin
                    if (!PWRITE || tx_full)
                        PSLVERR = 1'b1;
                end

                ADDR_RXDATA: begin
                    if (PWRITE || rx_empty)
                        PSLVERR = 1'b1;
                    else
                        PRDATA = {24'b0, rx_fifo[rx_rd_ptr]};
                end

                default: PSLVERR = 1'b1;
            endcase
        end
    end

    always_ff @(posedge PCLK) begin
        if (!PRESETn)
            ctrl_reg <= 32'h0000_0100;
        else if (apb_write && (PADDR == ADDR_CTRL))
            ctrl_reg <= PWDATA & 32'h0000_FF07;
    end

    // FIFO storage, pointers and occupancy have a single owner.
    integer i;
    always_ff @(posedge PCLK) begin
        if (!PRESETn) begin
            tx_wr_ptr <= '0;
            tx_rd_ptr <= '0;
            rx_wr_ptr <= '0;
            rx_rd_ptr <= '0;
            tx_count  <= '0;
            rx_count  <= '0;

            for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
                tx_fifo[i] <= '0;
                rx_fifo[i] <= '0;
            end
        end else begin
            if (tx_push) begin
                tx_fifo[tx_wr_ptr] <= PWDATA[7:0];
                tx_wr_ptr <= ptr_next(tx_wr_ptr);
            end

            if (tx_start)
                tx_rd_ptr <= ptr_next(tx_rd_ptr);

            if (rx_commit && !rx_full) begin
                rx_fifo[rx_wr_ptr] <= rx_commit_data;
                rx_wr_ptr <= ptr_next(rx_wr_ptr);
            end

            if (rx_pop)
                rx_rd_ptr <= ptr_next(rx_rd_ptr);

            case ({tx_push, tx_start})
                2'b10: tx_count <= tx_count + 1'b1;
                2'b01: tx_count <= tx_count - 1'b1;
                default: tx_count <= tx_count;
            endcase

            case ({rx_commit && !rx_full, rx_pop})
                2'b10: rx_count <= rx_count + 1'b1;
                2'b01: rx_count <= rx_count - 1'b1;
                default: rx_count <= rx_count;
            endcase
        end
    end

    // SPI master: one byte per transaction, MSB first.
    always_ff @(posedge PCLK) begin
        if (!PRESETn) begin
            busy           <= 1'b0;
            SCLK           <= 1'b0;
            MOSI           <= 1'b0;
            CS_n           <= 1'b1;
            tx_shift       <= 7'h00;
            rx_shift       <= 8'h00;
            sample_count   <= 4'd0;
            divider_count  <= 8'd0;
            spi_mode       <= 2'b00;
            leading_edge   <= 1'b1;
            tx_start       <= 1'b0;
            rx_commit      <= 1'b0;
            rx_commit_data <= 8'h00;
        end else begin
            tx_start  <= 1'b0;
            rx_commit <= 1'b0;
            spi_mode  <= ctrl_reg[2:1];

            if (!busy) begin
                SCLK          <= cpol;
                divider_count <= 8'd0;
                sample_count  <= 4'd0;
                leading_edge  <= 1'b1;

                if (ctrl_reg[0] && !tx_empty && !rx_full) begin
                    busy     <= 1'b1;
                    CS_n     <= 1'b0;
                    tx_start <= 1'b1;
                    tx_shift <= tx_fifo[tx_rd_ptr][6:0];
                    rx_shift <= 8'h00;
                    MOSI     <= tx_fifo[tx_rd_ptr][7];
                end else begin
                    CS_n <= 1'b1;
                end
            end else if (divider_count >= ((clk_div == 0) ? 0 : clk_div - 1'b1)) begin
                divider_count <= 8'd0;
                SCLK <= ~SCLK;

                if (leading_edge) begin
                    if (cpha) begin
                        // Keep the initial MSB through the first leading edge.
                        // Advance the remaining bits on subsequent leading edges.
                        if (sample_count != 4'd0) begin
                            MOSI     <= tx_shift[6];
                            tx_shift <= {tx_shift[5:0], 1'b0};
                        end
                    end else begin
                        rx_shift <= {rx_shift[6:0], MISO};
                    end
                end else begin
                    if (cpha) begin
                        rx_shift <= {rx_shift[6:0], MISO};
                    end else begin
                        MOSI     <= tx_shift[6];
                        tx_shift <= {tx_shift[5:0], 1'b0};
                    end
                end

                leading_edge <= ~leading_edge;

                if (!leading_edge) begin
                    if (sample_count == 4'd7) begin
                        busy           <= 1'b0;
                        CS_n           <= 1'b1;
                        rx_commit      <= 1'b1;
                        rx_commit_data <= cpha
                                        ? {rx_shift[6:0], MISO}
                                        : rx_shift;
                    end else begin
                        sample_count <= sample_count + 1'b1;
                    end
                end
            end else begin
                divider_count <= divider_count + 1'b1;
            end
        end
    end

endmodule
