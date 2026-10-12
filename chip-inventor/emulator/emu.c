#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <getopt.h>

#include "fpga_pci.h"
#include "fpga_mgmt.h"

#ifndef APP_PF_BAR0
#define APP_PF_BAR0 0
#endif

#define FPGA_SLOT   0
#define DELAY(_ms)  usleep(_ms * 1000);
#define DELAY_AXI() DELAY(50)

#define RESET_ADDR  0x00
#define IN_ADDR     0x04
#define OUT_ADDR    0x08
#define TX_ADDR     0x0C
#define RX0_ADDR    0x10
#define RX1_ADDR    0x14
#define RXN_ADDR    0x18
#define PC_ADDR     0x1C

typedef struct axi_register {
    uint32_t addr;
    uint32_t value;
} axi_register;

axi_register reset_reg =    {.addr = RESET_ADDR,    .value = 0};
axi_register in_reg =       {.addr = IN_ADDR,       .value = 0};
axi_register out_reg =      {.addr = OUT_ADDR,      .value = 0};
axi_register tx_reg =       {.addr = TX_ADDR,       .value = 0};
axi_register rx0_reg =      {.addr = RX0_ADDR,      .value = 0};
axi_register rx1_reg =      {.addr = RX1_ADDR,      .value = 0};
axi_register rxn_reg =      {.addr = RXN_ADDR,      .value = 0};
axi_register pc_reg =       {.addr = PC_ADDR,       .value = 0};

int fpga_write_addr(pci_bar_handle_t *pci, uint32_t addr, uint32_t value) {
    DELAY_AXI();
    
    int err = fpga_pci_poke(*pci, addr, value);
    
    if (err) {
        fprintf(stderr, "[error] Write error: %d\n", err);
    }

    return err;
}

int fpga_read_addr(pci_bar_handle_t *pci, uint32_t addr, uint32_t *value) {
    DELAY_AXI();
    
    int err = fpga_pci_peek(*pci, addr, value);

    if (err) {
        fprintf(stderr, "[error] Read error: %d\n", err);
    }

    return err;
}

int fpga_write(pci_bar_handle_t *pci, const axi_register *reg) {
    return fpga_write_addr(pci, reg->addr, reg->value);
}

int fpga_read(pci_bar_handle_t *pci, axi_register *reg) {
    return fpga_read_addr(pci, reg->addr, &reg->value);
}

int fpga_write_input(pci_bar_handle_t *pci, uint8_t value) {
    int err = 0;

    // Read
    err = fpga_read(pci, &in_reg);
    if(err) {
        fprintf(stderr, "[error] \"fpga_read\" error: %d\n", err);
        return err;
    }

    // Modify
    in_reg.value = (in_reg.value & 0xFF00) | (value);

    // Write
    err = fpga_write(pci, &in_reg);
    if(err) {
        fprintf(stderr, "[error] \"fpga_write\" error: %d\n", err);
        return err;
    }

    return 0;
}

int fpga_write_direction(pci_bar_handle_t *pci, uint8_t value) {
    int err = 0;

    // Read
    err = fpga_read(pci, &in_reg);
    if(err) {
        fprintf(stderr, "[error] \"fpga_read\" error: %d\n", err);
        return err;
    }

    // Modify
    in_reg.value = (in_reg.value & 0x00FF) | ((((uint16_t) value) << 8) & 0xFF00);

    // Write
    err = fpga_write(pci, &in_reg);
    if(err) {
        fprintf(stderr, "[error] \"fpga_write\" error: %d\n", err);
        return err;
    }

    return 0;
}

int fpga_reset(pci_bar_handle_t *pci) {
    int err = 0;
    
    // Reset FPGA
    err = fpga_write_addr(pci, RESET_ADDR, 0x1);
    if(err) {
        goto fpga_reset_end;
    }
    err = fpga_write_addr(pci, RESET_ADDR, 0x0);
    if(err) {
        goto fpga_reset_end;
    }
    err = fpga_write_addr(pci, RESET_ADDR, 0x1);
    if(err) {
        goto fpga_reset_end;
    }

fpga_reset_end:
    return err;
}

int fpga_init(pci_bar_handle_t *pci) {
    int err = 0;

    err = fpga_mgmt_init();
    if (err) {
        fprintf(stderr, "[error] FPGA init error: %d\n", err);
        goto fpga_init_end;
    }

    *pci = PCI_BAR_HANDLE_INIT;
    err = fpga_pci_attach(FPGA_SLOT, FPGA_APP_PF, APP_PF_BAR0, 0, pci);
    if (err) {
        fprintf(stderr, "[error] FPGA attach error: %d\n", err);
        goto fpga_init_end;
    }

    err = fpga_write_direction(pci, 0xF0);
    if (err) {
        fprintf(stderr, "[error] \"fpga_write_direction\" error: %d\n", err);
        goto fpga_init_end;
    }

    err = fpga_reset(pci);

fpga_init_end:
    return err;
}

void fpga_deinit(pci_bar_handle_t *pci) {
    fpga_pci_detach(*pci);
}

int fpga_read_uart(pci_bar_handle_t *pci, uint8_t *value, int n) {
    static uint8_t current_ptr = 0;

    if (n <= 0 || n > 8) {
        return 1; 
    }

    int err = 0;

    err = fpga_read(pci, &rx0_reg);
    if(err) {
        return err;
    }

    err = fpga_read(pci, &rx1_reg);
    if(err) {
        return err;
    }

    uint64_t uart_value = ((uint64_t) rx1_reg.value << 32) | (rx0_reg.value);

    for(int i = current_ptr; i < current_ptr + n; i++) {
        value[i - current_ptr] = (uart_value >> i * 8) & 0xFF;
    }

    current_ptr += n;

    return 0;
}

int fpga_write_uart(pci_bar_handle_t *pci, const uint8_t *value, int n) {
    for(int i = 0; i < n; i++) {
        int err = fpga_write_addr(pci, TX_ADDR, value[i]);
        if(err) {
            return err;
        }

        // Wait for TX to be done
        do {
            int err = fpga_read(pci, &tx_reg);
            if(err) {
                return err;
            }
        } while(!(tx_reg.value & (1 << 8)));
    }

    return 0;
}

int fpga_write_uart_reverse(pci_bar_handle_t *pci, const uint8_t *value, int n) {
    for(int i = n - 1; i >= 0; i--) {
        int err = fpga_write_addr(pci, TX_ADDR, value[i]);
        if(err) {
            return err;
        }

        // Wait for TX to be done
        do {
            int err = fpga_read(pci, &tx_reg);
            if(err) {
                return err;
            }
        } while(!(tx_reg.value & (1 << 8)));
    }

    return 0;
}

void show_help(const char *program) {
    fprintf(stderr, "\
            [usage] %s <options>\n\
            -h         show the usage.\n\
            -d DIR     set direction (1 for output and 0 for input).\n\
            -o DATA    read OUT (must be equal to DATA).\n\
            -i DATA    write DATA to IN.\n\
            -t1 DATA   transmit 1 byte with  DATA.\n\
            -t2 DATA   transmit 2 bytes with DATA.\n\
            -t4 DATA   transmit 4 bytes with DATA.\n\
            -r1 DATA   receive 1 byte (must be equal to DATA).\n\
            -r2 DATA   receive 2 bytes (must be equal to DATA).\n\
            -r4 DATA   receive 4 bytes (must be equal to DATA).\n"
            , program);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        show_help(argv[0]);
        return EXIT_FAILURE;

    }

    const static struct option LONG_OPTIONS[] = {
        {"h",  no_argument,       0, 'h'},
        {"o",  required_argument, 0, 'o'},
        {"d",  required_argument, 0, 'd'},
        {"i",  required_argument, 0, 'i'},
        {"t1", required_argument, 0, '0'},
        {"t2", required_argument, 0, '1'},
        {"t4", required_argument, 0, '2'},
        {"r1", required_argument, 0, '3'},
        {"r2", required_argument, 0, '4'},
        {"r4", required_argument, 0, '5'},
        {0, 0, 0, 0}
    };

    int err = 0;

    // Init FPGA
    pci_bar_handle_t pci;
    err = fpga_init(&pci);
    if(err) {
        fprintf(stderr, "[error] \"fpga_init\" error: %d\n", err);
        goto main_end;
    }
    else {
        fprintf(stdout, "[ok] RISC-V started!\n");
    }

    // // Read OUT (IDLE)
    // err = fpga_read(&pci, &out_reg);
    // if(err) {
    //     fprintf(stderr, "[error] \"fpga_read\"/OUT error: %d\n", err);
    //     goto main_end;
    // }
    // else if(out_reg.value != 0x1) {
    //     fprintf(stderr, "[error] Error reading OUT register (BUSY): is %d\n, should be 0", out_reg.value);
    //     goto main_end;
    // }
    // else {
    //     fprintf(stdout, "[ok] \"fpga_read\"/OUT\n");
    // }

    // // Write IN (TRIGGER = 1)
    // err = fpga_write_input(&pci, 0x2);
    // if(err) {
    //     fprintf(stderr, "[error] \"fpga_write_input\"error: %d\n", err);
    //     goto main_end;
    // }
    // else {
    //     fprintf(stdout, "[ok] \"fpga_write_input\"\n");
    // }

    // // Write IN (TRIGGER = 0)
    // err = fpga_write_input(&pci, 0x0);
    // if(err) {
    //     fprintf(stderr, "[error] \"fpga_write_input\"error: %d\n", err);
    //     goto main_end;
    // }
    // else {
    //     fprintf(stdout, "[ok] \"fpga_write_input\"\n");
    // }

    // // Read OUT (BUSY)
    // err = fpga_read(&pci, &out_reg);
    // if(err) {
    //     fprintf(stderr, "[error] \"fpga_read\"/OUT error: is %d\n, should be 0\n", err);
    //     goto main_end;
    // }
    // else if(out_reg.value != 0x0) {
    //     fprintf(stderr, "[error] Error reading OUT register (IDLE): %d\n", out_reg.value);
    //     goto main_end;
    // }
    // else {
    //     fprintf(stdout, "[ok] \"fpga_read\"/OUT\n");
    // }

    int opt;
    while ((opt = getopt_long_only(argc, argv, "h", LONG_OPTIONS, NULL)) != -1) {
        uint64_t value;

        switch (opt) {
            case 'h':
                show_help(argv[0]);
                err = EXIT_SUCCESS;
                goto main_end;

            case 'o':
                value = strtoul(optarg, NULL, 0);

                uint32_t out_value;
                err = fpga_read_addr(&pci, OUT_ADDR, &out_value);
                if(err) {
                    fprintf(stderr, "[error] \"fpga_read_addr\" error: %d\n", err);
                    goto main_end;
                }
                else if(value != out_value) {
                    fprintf(stderr, "[error] OUT read error. Expected 0x%08X. Got 0x%08X\n", (uint32_t) value, (uint32_t) out_value);
                    goto main_end;
                }
                else {
                    fprintf(stdout, "[ok] Read 0x%08X from OUTPUT PINS\n",out_value );
                }
                break;

            case 'i':
                value = strtoul(optarg, NULL, 0);

                err = fpga_write_input(&pci, value);
                if(err) {
                    fprintf(stderr, "[error] \"fpga_write_input\" error: %d\n", err);
                    goto main_end;
                }
                else {
                    fprintf(stdout, "[ok] Written 0x%08X to INPUT PINS\n", (uint32_t) value);
                }
                break;

            case 'd':
                value = strtoul(optarg, NULL, 0);

                err = fpga_write_direction(&pci, value);
                if(err) {
                    fprintf(stderr, "[error] \"fpga_write_direction\"error: %d\n", err);
                    goto main_end;
                }
                else {
                    fprintf(stdout, "[ok] Written 0x%08X to DIRECTION\n", (uint32_t) value);
                }
                break;

            case '0':
                value = strtoul(optarg, NULL, 0);
                err = fpga_write_uart(&pci, (const uint8_t *) &value, 1);
                if(err) {
                    fprintf(stderr, "[error] \"fpga_write_uart\" error: %d\n", err);
                    goto main_end;
                }
                else {
                    fprintf(stdout, "[ok] Written 0x%02X to UART RX\n", (uint32_t) value);
                }
                break;

            case '1':
                value = strtoul(optarg, NULL, 0);
                err = fpga_write_uart(&pci, (const uint8_t *) &value, 2);
                if(err) {
                    fprintf(stderr, "[error] \"fpga_write_uart\" error: %d\n", err);
                    goto main_end;
                }
                else {
                    fprintf(stdout, "[ok] Written 0x%04X to UART RX\n", (uint32_t) value);
                }
                break;

            case '2':
                value = strtoul(optarg, NULL, 0);
                err = fpga_write_uart(&pci, (const uint8_t *) &value, 4);
                if(err) {
                    fprintf(stderr, "[error] \"fpga_write_uart\" error: %d\n", err);
                    goto main_end;
                }
                else {
                    fprintf(stdout, "[ok] Written 0x%08X to UART RX\n", (uint32_t) value);
                }
                break;

            case '3': {
                value = strtoul(optarg, NULL, 0);

                uint8_t uart_value;
                err = fpga_read_uart(&pci, (uint8_t *) &uart_value, 1);
                if(err) {
                    fprintf(stderr, "[error] \"fpga_read_uart\" error: %d\n", err);
                    goto main_end;
                }
                else if(value != uart_value) {
                    fprintf(stderr, "[error] UART read error. Expected 0x%02X. Got 0x%02X\n", (uint8_t) value, (uint8_t) uart_value);
                    goto main_end;
                }
                else {
                    fprintf(stdout, "[ok] Read 0x%02X from UART TX\n", uart_value);
                }
                break;
            }

            case '4': {
                value = strtoul(optarg, NULL, 0);

                uint16_t uart_value;
                err = fpga_read_uart(&pci, (uint8_t *) &uart_value, 2);
                if(err) {
                    fprintf(stderr, "[error] \"fpga_read_uart\" error: %d\n", err);
                    goto main_end;
                }
                else if(value != uart_value) {
                    fprintf(stderr, "[error] UART read error. Expected 0x%04X. Got 0x%04X\n", (uint16_t) value, (uint16_t) uart_value);
                    goto main_end;
                }
                else {
                    fprintf(stdout, "[ok] Read 0x%04X from UART TX\n", uart_value);
                }
                break;
            }

            case '5': {
                value = strtoul(optarg, NULL, 0);

                uint32_t uart_value;
                err = fpga_read_uart(&pci, (uint8_t *) &uart_value, 4);
                if(err) {
                    fprintf(stderr, "[error] \"fpga_read_uart\" error: %d\n", err);
                    goto main_end;
                }
                else if(value != uart_value) {
                    fprintf(stderr, "[error] UART read error. Expected 0x%08X. Got 0x%08X\n", (uint32_t) value, (uint32_t) uart_value);
                    goto main_end;
                }
                else {
                    fprintf(stdout, "[ok] Read 0x%08X from UART TX\n", uart_value);
                }
                break;
            }

            case '?':
            default:
                show_help(argv[0]);
                err = EXIT_FAILURE;
                goto main_end;
        }
    }

    // Deinit FPGA
main_end:
    fpga_deinit(&pci);
    return err ? EXIT_SUCCESS : EXIT_FAILURE;
}