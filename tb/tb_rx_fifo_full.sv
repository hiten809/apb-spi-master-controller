`timescale 1ns/1ps

module tb_rx_fifo_full #(
    parameter integer SPI_MODE = 0
);

    localparam logic [31:0] ADDR_CTRL   = 32'h0000_0000;
    localparam logic [31:0] ADDR_STATUS = 32'h0000_0004;
    localparam logic [31:0] ADDR_TXDATA = 32'h0000_0008;
    localparam logic [31:0] ADDR_RXDATA = 32'h0000_000C;

    localparam integer FIFO_DEPTH = 4;
    localparam integer NUM_TRANSFERS = 5;
    localparam logic CPOL = (SPI_MODE >> 1) & 1;
    localparam logic CPHA = SPI_MODE & 1;

    logic PCLK = 0, PRESETn = 0;
    logic PSEL = 0, PENABLE = 0, PWRITE = 0;
    logic [31:0] PADDR = 0, PWDATA = 0, PRDATA;
    logic PREADY, PSLVERR;

    logic SCLK, MOSI, MISO = 0, CS_n;
    logic [7:0] slave_shift = 0;

    logic [7:0] tx_patterns [0:NUM_TRANSFERS-1];
    logic [7:0] rx_patterns [0:NUM_TRANSFERS-1];

    integer transaction_count = 0;
    integer sampled_bits = 0;
    integer rx_full_events = 0;
    integer pause_checks = 0;
    integer resume_events = 0;
    integer rx_data_checks = 0;
    integer cycles;
    integer i;
    logic [31:0] read_data;

    apb_spi_master dut (
        .PCLK(PCLK), .PRESETn(PRESETn),
        .PSEL(PSEL), .PENABLE(PENABLE),
        .PWRITE(PWRITE), .PADDR(PADDR), .PWDATA(PWDATA),
        .PRDATA(PRDATA), .PREADY(PREADY), .PSLVERR(PSLVERR),
        .SCLK(SCLK), .MOSI(MOSI), .MISO(MISO), .CS_n(CS_n)
    );

    always #5 PCLK = ~PCLK;

    task automatic apb_write(
        input logic [31:0] addr,
        input logic [31:0] data
    );
        begin
            @(negedge PCLK);
            PSEL = 1; PENABLE = 0; PWRITE = 1;
            PADDR = addr; PWDATA = data;

            @(negedge PCLK);
            PENABLE = 1;
            #1;
            if (!PREADY || PSLVERR)
                $fatal(1, "APB write failed: addr=%h PSLVERR=%b",
                       addr, PSLVERR);

            @(posedge PCLK);
            #1;
            @(negedge PCLK);
            PSEL = 0; PENABLE = 0; PWRITE = 0;
        end
    endtask

    task automatic apb_read(
        input logic [31:0] addr,
        output logic [31:0] data
    );
        begin
            @(negedge PCLK);
            PSEL = 1; PENABLE = 0; PWRITE = 0; PADDR = addr;

            @(negedge PCLK);
            PENABLE = 1;
            #1;
            if (!PREADY || PSLVERR)
                $fatal(1, "APB read failed: addr=%h PSLVERR=%b",
                       addr, PSLVERR);
            data = PRDATA;

            @(negedge PCLK);
            PSEL = 0; PENABLE = 0;
        end
    endtask

    // Start each slave response on the master's CS assertion.
    always @(negedge CS_n) begin
        if (PRESETn) begin
            if (transaction_count >= NUM_TRANSFERS)
                $fatal(1, "Unexpected extra SPI transaction");

            slave_shift = rx_patterns[transaction_count];
            MISO = CPHA ? 1'b0 : rx_patterns[transaction_count][7];
            sampled_bits = 0;
            transaction_count = transaction_count + 1;
        end
    end

    // Behavioral slave: update MISO on the SPI change edge.
    always @(SCLK) begin
        if (!CS_n && PRESETn) begin
            if (SCLK != CPOL) begin
                if (CPHA)
                    MISO = slave_shift[7];
            end else begin
                slave_shift <= {slave_shift[6:0], 1'b0};
                if (!CPHA)
                    MISO <= slave_shift[6];
            end
        end
    end

    initial begin
        tx_patterns[0] = 8'h31;
        tx_patterns[1] = 8'h42;
        tx_patterns[2] = 8'h53;
        tx_patterns[3] = 8'h64;
        tx_patterns[4] = 8'h75;

        rx_patterns[0] = 8'hA1;
        rx_patterns[1] = 8'hB2;
        rx_patterns[2] = 8'hC3;
        rx_patterns[3] = 8'hD4;
        rx_patterns[4] = 8'hE5;

        $dumpfile("results/rx_fifo_full.vcd");
        $dumpvars(0, tb_rx_fifo_full);

        repeat (3) @(negedge PCLK);
        PRESETn = 1;

        // Configure divider=2 and mode while disabled.
        apb_write(ADDR_CTRL, 32'h0000_0200 | (SPI_MODE << 1));

        // Queue five bytes; TX FIFO depth is four, so enqueue four first.
        for (i = 0; i < FIFO_DEPTH; i = i + 1)
            apb_write(ADDR_TXDATA, {24'b0, tx_patterns[i]});

        // Enable; first four responses should fill RX FIFO.
        apb_write(ADDR_CTRL, 32'h0000_0201 | (SPI_MODE << 1));

        cycles = 0;
        while (cycles < 2000) begin
            apb_read(ADDR_STATUS, read_data);
            if (read_data[3] && !read_data[0])
                cycles = 2000;
            else begin
                cycles = cycles + 1;
                repeat (2) @(negedge PCLK);
            end
        end

        if (!read_data[3] || read_data[4])
            $fatal(1, "RX FIFO did not reach full state; STATUS=%h",
                   read_data);
        rx_full_events = rx_full_events + 1;

        if (transaction_count != FIFO_DEPTH)
            $fatal(1, "Expected %0d transfers before full, observed %0d",
                   FIFO_DEPTH, transaction_count);

        // Queue the fifth byte while RX FIFO is full.
        apb_write(ADDR_CTRL, 32'h0000_0200 | (SPI_MODE << 1));
        apb_write(ADDR_TXDATA, {24'b0, tx_patterns[4]});
        apb_write(ADDR_CTRL, 32'h0000_0201 | (SPI_MODE << 1));

        repeat (20) @(negedge PCLK);
        pause_checks = pause_checks + 1;
        if (transaction_count != FIFO_DEPTH)
            $fatal(1, "Master started another transfer while RX FIFO full");

        // Free one RX slot. The fifth transfer should now be able to start.
        apb_read(ADDR_RXDATA, read_data);
        if (read_data[7:0] !== rx_patterns[0])
            $fatal(1, "RX FIFO order error at first item: got %02h",
                   read_data[7:0]);
        rx_data_checks = rx_data_checks + 1;

        cycles = 0;
        while (cycles < 2000 && transaction_count < NUM_TRANSFERS) begin
            cycles = cycles + 1;
            @(negedge PCLK);
        end

        if (transaction_count != NUM_TRANSFERS)
            $fatal(1, "Fifth transfer did not resume after RX read");
        resume_events = resume_events + 1;

        // Wait for the fifth response to be committed to RX FIFO.
        cycles = 0;
        while (cycles < 2000) begin
            apb_read(ADDR_STATUS, read_data);
            if (read_data[3] && !read_data[0])
                cycles = 2000;
            else begin
                cycles = cycles + 1;
                repeat (2) @(negedge PCLK);
            end
        end

        // Confirm the fifth response filled RX FIFO and the engine is idle.
        if (!read_data[3] || read_data[0])
            $fatal(1, "RX FIFO failed to return to full/idle after recovery; STATUS=%h",
                   read_data);
        rx_full_events = rx_full_events + 1;

        // Remaining FIFO order must be responses 1..4.
        for (i = 1; i < NUM_TRANSFERS; i = i + 1) begin
            apb_read(ADDR_RXDATA, read_data);
            if (read_data[7:0] !== rx_patterns[i])
                $fatal(1, "RX[%0d] mismatch: expected %02h got %02h",
                       i, rx_patterns[i], read_data[7:0]);
            rx_data_checks = rx_data_checks + 1;
        end

        apb_read(ADDR_STATUS, read_data);
        if (!read_data[4] || read_data[3])
            $fatal(1, "RX FIFO should be empty after draining; STATUS=%h",
                   read_data);

        $display("COVERAGE: RX full events=%0d/2, pause checks=%0d/1, resume events=%0d/1, RX bytes verified=%0d/%0d",
                 rx_full_events, pause_checks, resume_events,
                 rx_data_checks, NUM_TRANSFERS);
        if (rx_full_events != 2 || pause_checks != 1 ||
            resume_events != 1 || rx_data_checks != NUM_TRANSFERS)
            $fatal(1, "RX FIFO functional coverage target not met");

        $display("PASS: RX FIFO full/pause/recovery, SPI mode %0d", SPI_MODE);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "Global timeout in RX FIFO-full test");
    end

endmodule
