`timescale 1ns/1ps

module tb_spi_transfer #(
    parameter integer SPI_MODE = 0,
    parameter logic [7:0] TX_DATA = 8'h3C,
    parameter logic [7:0] SLAVE_RESPONSE = 8'hA5
);

    localparam logic [31:0] ADDR_CTRL   = 32'h0000_0000;
    localparam logic [31:0] ADDR_STATUS = 32'h0000_0004;
    localparam logic [31:0] ADDR_TXDATA = 32'h0000_0008;
    localparam logic [31:0] ADDR_RXDATA = 32'h0000_000C;

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

    logic SCLK;
    logic MOSI;
    logic MISO = 0;
    logic CS_n;

    localparam logic CPOL = (SPI_MODE >> 1) & 1;
    localparam logic CPHA = SPI_MODE & 1;

    logic [7:0] slave_shift = SLAVE_RESPONSE;
    logic [7:0] master_observed = 8'h00;
    integer sampled_bits = 0;

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

    // Behavioral SPI slave.
    // CPHA=0: present each bit before the leading edge, then advance
    // the response on the trailing edge.
    // CPHA=1: present each bit on the leading edge, hold it through
    // the trailing edge where the master samples it.
    always @(negedge CS_n) begin
        slave_shift = SLAVE_RESPONSE;
        master_observed = 8'h00;
        sampled_bits = 0;
        MISO = CPHA ? 1'b0 : SLAVE_RESPONSE[7];
    end

    // Behavioral slave: drive MISO and shift the response byte.
    always @(SCLK) begin
        if (!CS_n && PRESETn) begin
            if (SCLK != CPOL) begin
                // Leading edge.
                if (CPHA) begin
                    MISO = slave_shift[7];
                end
            end else begin
                // Trailing edge.
                if (CPHA) begin
                    slave_shift <= {slave_shift[6:0], 1'b0};
                end else begin
                    slave_shift <= {slave_shift[6:0], 1'b0};
                    MISO <= slave_shift[6];
                end
            end
            $display("SPI mode %0d edge: SCLK=%b MOSI=%b MISO=%b at %0t",
                     SPI_MODE, SCLK, MOSI, MISO, $time);
        end
    end

    // Sample MOSI on the SPI sampling edge.
    // Permit the final bit even if CS_n rises in the same timestep.
    always @(SCLK) begin : spi_tx_monitor
        logic sample_edge;

        sample_edge = (CPHA && (SCLK == CPOL)) ||
                      (!CPHA && (SCLK != CPOL));

        if (PRESETn && sample_edge && sampled_bits < 8 &&
            (!CS_n || sampled_bits == 7)) begin
            $display("TX MONITOR mode=%0d index=%0d SCLK=%b CPOL=%b CPHA=%b CS_n=%b MOSI=%b time=%0t",
                     SPI_MODE, sampled_bits, SCLK, CPOL, CPHA, CS_n, MOSI, $time);
            master_observed = {master_observed[6:0], MOSI};
            sampled_bits = sampled_bits + 1;
        end
    end

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
            #1;
            if (!PREADY || PSLVERR)
                $fatal(1, "APB write failed at %h", addr);

            @(negedge PCLK);
            PSEL = 0;
            PENABLE = 0;
            PWRITE = 0;
        end
    endtask

    task automatic apb_read(input logic [31:0] addr,
                            output logic [31:0] data);
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

    logic [31:0] read_data;
    integer cycles;

    initial begin
        $dumpfile($sformatf("apb-spi-results/waveforms/spi_mode%0d.vcd", SPI_MODE));
        $dumpvars(0, tb_spi_transfer);

        repeat (3) @(negedge PCLK);
        PRESETn = 1;

        // Mode 0, divider = 2, SPI initially disabled.
        apb_write(ADDR_CTRL, (32'h0000_0200 | (SPI_MODE << 1)));

        // Queue byte 0x3C, then enable the SPI master.
        apb_write(ADDR_TXDATA, {24'h0, TX_DATA});
        apb_write(ADDR_CTRL, (32'h0000_0201 | (SPI_MODE << 1)));

        // Wait for the transfer to finish.
        cycles = 0;
        while (CS_n == 1'b0 && cycles < 1)
            cycles = cycles + 1;

        while (cycles < 500) begin
            apb_read(ADDR_STATUS, read_data);
            if (read_data[0] == 1'b0 && read_data[4] == 1'b0)
                cycles = 500;
            else begin
                cycles = cycles + 1;
                repeat (2) @(negedge PCLK);
            end
        end

        if (read_data[4] !== 1'b0)
            $fatal(1, "RX FIFO remained empty; STATUS=%h", read_data);

        apb_read(ADDR_RXDATA, read_data);

        // Allow behavioral-slave nonblocking assignments to settle.
        #1;

        if (master_observed !== TX_DATA)
            $fatal(1, "TX mismatch: expected %02h, slave observed %02h",
                   TX_DATA, master_observed);

        if (sampled_bits != 8)
            $fatal(1, "Incorrect SPI sample count: expected 8, got %0d",
                   sampled_bits);

        $display("TX verified: %02h (expected %02h), sampled bits: %0d",
                 master_observed, TX_DATA, sampled_bits);
        $display("Received byte: %02h (expected %02h)",
                 read_data[7:0], SLAVE_RESPONSE);

        if (read_data[7:0] !== SLAVE_RESPONSE)
            $fatal(1, "RX mismatch: expected %02h, got %02h",
                   SLAVE_RESPONSE, read_data[7:0]);

        $display("PASS: SPI mode %0d transfer", SPI_MODE);
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "Global timeout: SPI transfer did not complete");
    end

endmodule
