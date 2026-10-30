`timescale 1ns/1ps

module tb_apb_spi_master;

    logic        PCLK = 0;
    logic        PRESETn = 0;
    logic        PSEL = 0;
    logic        PENABLE = 0;
    logic        PWRITE = 0;
    logic [31:0] PADDR = 0;
    logic [31:0] PWDATA = 0;
    logic [31:0] PRDATA;
    logic        PREADY;
    logic        PSLVERR;
    logic        SCLK;
    logic        MOSI;
    logic        MISO = 0;
    logic        CS_n;

    integer successful_writes = 0;
    integer successful_reads = 0;
    integer expected_errors = 0;

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

    task automatic apb_write(input logic [31:0] addr,
                             input logic [31:0] data);
        begin
            @(negedge PCLK);
            PSEL = 1;
            PENABLE = 0;
            PWRITE = 1;
            PADDR = addr;
            PWDATA = data;

            @(negedge PCLK);
            PENABLE = 1;

            @(posedge PCLK);
            if (!PREADY || PSLVERR)
                $fatal(1, "APB write failed: addr=%h", addr);
            successful_writes = successful_writes + 1;

            @(negedge PCLK);
            PSEL = 0;
            PENABLE = 0;
            PWRITE = 0;
        end
    endtask

    task automatic apb_read_check(input logic [31:0] addr,
                                  input logic [31:0] expected);
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
                $fatal(1, "APB read failed: addr=%h", addr);

            if (PRDATA !== expected)
                $fatal(1, "Read mismatch at %h: expected %h, got %h",
                       addr, expected, PRDATA);
            successful_reads = successful_reads + 1;

            @(negedge PCLK);
            PSEL = 0;
            PENABLE = 0;
        end
    endtask


    task automatic apb_write_expect_error(input logic [31:0] addr,
                                          input logic [31:0] data);
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
            if (!PREADY || !PSLVERR)
                $fatal(1, "Expected APB error at address %h", addr);
            expected_errors = expected_errors + 1;

            @(negedge PCLK);
            PSEL = 0;
            PENABLE = 0;
            PWRITE = 0;
        end
    endtask

    task automatic apb_read_expect_error(input logic [31:0] addr);
        begin
            @(negedge PCLK);
            PSEL = 1;
            PENABLE = 0;
            PWRITE = 0;
            PADDR = addr;

            @(negedge PCLK);
            PENABLE = 1;
            #1;
            if (!PREADY || !PSLVERR)
                $fatal(1, "Expected APB read error at address %h", addr);
            expected_errors = expected_errors + 1;

            @(negedge PCLK);
            PSEL = 0;
            PENABLE = 0;
        end
    endtask

    initial begin
        $dumpfile("results/apb_registers.vcd");
        $dumpvars(0, tb_apb_spi_master);

        repeat (2) @(negedge PCLK);
        PRESETn = 1;

        apb_read_check(32'h0000_0000, 32'h0000_0100);
        apb_write(32'h0000_0000, 32'h0000_0500);
        apb_read_check(32'h0000_0000, 32'h0000_0500);
        apb_read_check(32'h0000_0004, 32'h0000_0014);

        // Fill the four-entry TX FIFO.
        apb_write(32'h0000_0008, 32'h0000_0011);
        apb_write(32'h0000_0008, 32'h0000_0022);
        apb_write(32'h0000_0008, 32'h0000_0033);
        apb_write(32'h0000_0008, 32'h0000_0044);

        // TX full (bit 1), RX empty (bit 4).
        apb_read_check(32'h0000_0004, 32'h0000_0012);

        // Fifth write must be rejected because TX FIFO is full.
        apb_write_expect_error(32'h0000_0008, 32'h0000_0055);

        // Invalid access permissions and empty RX FIFO must report errors.
        apb_write_expect_error(32'h0000_0004, 32'h0000_0000); // STATUS is read-only
        apb_read_expect_error(32'h0000_0008);                 // TXDATA is write-only
        apb_read_expect_error(32'h0000_000C);                 // RXDATA empty: underflow
        apb_read_expect_error(32'h0000_0010);                 // Unmapped address

        $display("COVERAGE: successful writes=%0d/5, successful reads=%0d/4, expected errors=%0d/5",
                 successful_writes, successful_reads, expected_errors);

        if (successful_writes != 5 || successful_reads != 4 ||
            expected_errors != 5)
            $fatal(1, "APB functional coverage target not met");

        $display("PASS: APB registers, TX FIFO overflow, and APB error checks");
        $finish;
    end

endmodule
