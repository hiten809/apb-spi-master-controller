`timescale 1ns/1ps

module tb_spi_multi_transfer #(
    parameter integer SPI_MODE = 0
);

    localparam logic [31:0] ADDR_CTRL   = 32'h0000_0000;
    localparam logic [31:0] ADDR_STATUS = 32'h0000_0004;
    localparam logic [31:0] ADDR_TXDATA = 32'h0000_0008;
    localparam logic [31:0] ADDR_RXDATA = 32'h0000_000C;

    localparam integer NUM_TRANSFERS = 4;
    localparam logic CPOL = (SPI_MODE >> 1) & 1;
    localparam logic CPHA = SPI_MODE & 1;

    logic PCLK = 0;
    logic PRESETn = 0;
    logic PSEL = 0;
    logic PENABLE = 0;
    logic PWRITE = 0;
    logic [31:0] PADDR = 0;
    logic [31:0] PWDATA = 0;
    logic [31:0] PRDATA;
    logic PREADY;
    logic PSLVERR;

    logic SCLK;
    logic MOSI;
    logic MISO = 0;
    logic CS_n;

    logic [7:0] slave_shift = 0;
    integer transaction_index = -1;
    integer sampled_bits = 0;
    logic [7:0] observed_tx = 0;
    logic [7:0] observed_tx_patterns [0:NUM_TRANSFERS-1];

    logic [7:0] tx_patterns [0:NUM_TRANSFERS-1];
    logic [7:0] rx_patterns [0:NUM_TRANSFERS-1];

    integer i;
    integer cycles;
    logic [31:0] read_data;

    apb_spi_master dut (
        .PCLK(PCLK),
        .PRESETn(PRESETn),
        .PSEL(PSEL),
        .PENABLE(PENABLE),
        .PWRITE(PWRITE),
        .PADDR(PADDR),
        .PWDATA(PWDATA),
        .PRDATA(PRDATA),
        .PREADY(PREADY),
        .PSLVERR(PSLVERR),
        .SCLK(SCLK),
        .MOSI(MOSI),
        .MISO(MISO),
        .CS_n(CS_n)
    );

    always #5 PCLK = ~PCLK;

    task automatic apb_write(
        input logic [31:0] addr,
        input logic [31:0] data
    );
        begin
            @(negedge PCLK);
            PSEL = 1;
            PENABLE = 0;
            PWRITE = 1;
            PADDR = addr;
            PWDATA = data;

            @(negedge PCLK);
            PENABLE = 1;

            #1;
            if (!PREADY || PSLVERR)
                $fatal(1, "APB write failed before acceptance: addr=%h data=%h PREADY=%b PSLVERR=%b tx_count=%0d tx_full=%b",
                       addr, data, PREADY, PSLVERR, dut.tx_count, dut.tx_full);

            @(posedge PCLK);
            #1;

            @(negedge PCLK);
            PSEL = 0;
            PENABLE = 0;
            PWRITE = 0;
        end
    endtask

    task automatic apb_read(
        input logic [31:0] addr,
        output logic [31:0] data
    );
        begin
            @(negedge PCLK);
            PSEL = 1;
            PENABLE = 0;
            PWRITE = 0;
            PADDR = addr;

            @(negedge PCLK);
            PENABLE = 1;
            #1;
            if (!PREADY || PSLVERR)
                $fatal(1, "APB read failed at %h", addr);

            data = PRDATA;

            @(negedge PCLK);
            PSEL = 0;
            PENABLE = 0;
        end
    endtask

    // Save the transmitted byte when each SPI transaction ends.
    always @(posedge CS_n) begin
        if (PRESETn && transaction_index >= 0 &&
            transaction_index < NUM_TRANSFERS)
            observed_tx_patterns[transaction_index] = observed_tx;
    end

    // Prepare one distinct response for each asserted chip-select.
    always @(negedge CS_n) begin
        transaction_index = transaction_index + 1;
        if (transaction_index >= NUM_TRANSFERS)
            $fatal(1, "Unexpected extra SPI transaction");

        slave_shift = rx_patterns[transaction_index];
        observed_tx = 0;
        sampled_bits = 0;
        MISO = CPHA ? 1'b0 : rx_patterns[transaction_index][7];

        $display("Starting transfer %0d: expected TX=%02h RX=%02h",
                 transaction_index,
                 tx_patterns[transaction_index],
                 rx_patterns[transaction_index]);
    end

    // Behavioral SPI slave response.
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

    // Observe the master's transmitted byte on each SPI sampling edge.
    always @(SCLK) begin
        logic sample_edge;
        sample_edge = (CPHA && (SCLK == CPOL)) ||
                      (!CPHA && (SCLK != CPOL));

        if (PRESETn && sample_edge && sampled_bits < 8 &&
            (!CS_n || sampled_bits == 7)) begin
            observed_tx = {observed_tx[6:0], MOSI};
            sampled_bits = sampled_bits + 1;
        end
    end

    initial begin
        tx_patterns[0] = 8'h3C;
        tx_patterns[1] = 8'h96;
        tx_patterns[2] = 8'hAA;
        tx_patterns[3] = 8'hF0;

        rx_patterns[0] = 8'hA5;
        rx_patterns[1] = 8'h5A;
        rx_patterns[2] = 8'h55;
        rx_patterns[3] = 8'h0F;

        $dumpfile("results/spi_multi_mode.vcd");
        $dumpvars(0, tb_spi_multi_transfer);

        repeat (3) @(negedge PCLK);
        PRESETn = 1;

        // Configure mode and divider while SPI is disabled.
        apb_write(ADDR_CTRL, 32'h0000_0200 | (SPI_MODE << 1));

        // Queue four bytes, fitting the TX FIFO depth.
        for (i = 0; i < NUM_TRANSFERS; i = i + 1) begin
            $display("Before TX enqueue[%0d]: data=%02h tx_count=%0d",
                     i, tx_patterns[i], dut.tx_count);
            apb_write(ADDR_TXDATA, {24'h0, tx_patterns[i]});
        end

        // Enable the master; it should process the queued bytes in order.
        apb_write(ADDR_CTRL, 32'h0000_0201 | (SPI_MODE << 1));

        // Wait for all four RX bytes, while checking for a timeout.
        cycles = 0;
        read_data = 0;
        while (cycles < 1500) begin
            apb_read(ADDR_STATUS, read_data);
            if (read_data[4] == 1'b0 &&
                read_data[0] == 1'b0 &&
                read_data[3] == 1'b0) begin
                // RX FIFO is nonempty and the engine is idle.
                // Read the available bytes below.
                cycles = 1500;
            end else begin
                cycles = cycles + 1;
                repeat (2) @(negedge PCLK);
            end
        end

        // Require the engine to have completed all queued transactions.
        if (transaction_index != NUM_TRANSFERS - 1)
            $fatal(1, "Expected %0d transfers, observed %0d",
                   NUM_TRANSFERS, transaction_index + 1);

        // Validate every transmitted byte captured from MOSI.
        for (i = 0; i < NUM_TRANSFERS; i = i + 1) begin
            if (observed_tx_patterns[i] !== tx_patterns[i])
                $fatal(1, "Mode %0d TX[%0d] mismatch: expected %02h got %02h",
                       SPI_MODE, i, tx_patterns[i], observed_tx_patterns[i]);
            $display("TX[%0d] verified: %02h", i, observed_tx_patterns[i]);
        end

        // Read and validate every response in FIFO order.
        for (i = 0; i < NUM_TRANSFERS; i = i + 1) begin
            apb_read(ADDR_STATUS, read_data);
            if (read_data[4] !== 1'b0)
                $fatal(1, "RX FIFO unexpectedly empty at item %0d", i);

            apb_read(ADDR_RXDATA, read_data);
            if (read_data[7:0] !== rx_patterns[i])
                $fatal(1, "Mode %0d RX[%0d] mismatch: expected %02h got %02h",
                       SPI_MODE, i, rx_patterns[i], read_data[7:0]);

            $display("RX[%0d] verified: %02h", i, read_data[7:0]);
        end

        $display("PASS: SPI mode %0d multi-transfer test", SPI_MODE);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Global timeout in multi-transfer test");
    end

endmodule
