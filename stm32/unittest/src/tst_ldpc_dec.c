/* 
  FILE...: ldpc_dec.c
  AUTHOR.: Matthew C. Valenti, Rohit Iyer Seshadri, David Rowe, Don Reid
  CREATED: Sep 2016

  Command line C LDPC decoder derived from MpDecode.c in the CML
  library.  Allows us to run the same decoder in Octave and C.  The
  code is defined by the parameters and array stored in the include
  file below, which can be machine generated from the Octave function
  ldpc_fsk_lib.m:ldpc_decode()

  The include file also contains test input/output vectors for the LDPC
  decoder for testing this program.  If no input file "stm_in.raw" is found
  then the built in test mode will run.

  If there is an input is should be encoded data from the x86 ldpc_enc
  program.  Here is the suggested way to run:

    ldpc_enc /dev/zero stm_in.raw --sd --code HRA_112_112 --testframes 10

    ldpc_dec stm_in.raw ref_out.raw --code HRA_112_112

    <Load stm32 and run>

    cmp -l ref_out.raw stm_out.raw
*/

#include <assert.h>
#include <errno.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "mpdecode_core.h"
#include "ofdm_internal.h"

#include "semihosting.h"
#include "stm32f4xx_conf.h"
#include "stm32f4xx.h"
#include "machdep.h"

/* generated by ldpc_fsk_lib.m:ldpc_decode() */
/* Machine generated consts, H_rows, H_cols, test input/output data to
   change LDPC code regenerate this file. */

#include "HRA_112_112.h"  

int testframes = 1;

int main(int argc, char *argv[]) {    
    int         CodeLength, NumberParityBits;
    int         i, r, num_ok, num_runs, parityCheckCount, state, next_state;
    char        out_char[HRA_112_112_CODELENGTH], *adetected_data;
    struct LDPC ldpc;
    float       *ainput;
    int         data_bits_per_frame;
    FILE        *fin, *fout;
    int         iter, total_iters;
    int         Tbits, Terrs, Tbits_raw, Terrs_raw;

    semihosting_init();

    fprintf(stderr, "LDPC decode test and profile\n");

    PROFILE_VAR(ldpc_decode);
    machdep_profile_init();

    ldpc.max_iter = HRA_112_112_MAX_ITER;
    ldpc.dec_type = 0;
    ldpc.q_scale_factor = 1;
    ldpc.r_scale_factor = 1;
    ldpc.CodeLength = HRA_112_112_CODELENGTH;
    ldpc.NumberParityBits = HRA_112_112_NUMBERPARITYBITS;
    ldpc.NumberRowsHcols = HRA_112_112_NUMBERROWSHCOLS;
    ldpc.max_row_weight = HRA_112_112_MAX_ROW_WEIGHT;
    ldpc.max_col_weight = HRA_112_112_MAX_COL_WEIGHT;
    ldpc.H_rows = HRA_112_112_H_rows;
    ldpc.H_cols = HRA_112_112_H_cols;
    ainput = HRA_112_112_input;
    adetected_data = HRA_112_112_detected_data;

    CodeLength = ldpc.CodeLength;
    NumberParityBits = ldpc.NumberParityBits;
    data_bits_per_frame = ldpc.NumberRowsHcols;
    unsigned char ibits[data_bits_per_frame];
    unsigned char pbits[NumberParityBits];

//    // Allocate common space which can be shared with other functions.
//    int         size_common;
//    uint8_t     *common_array;

//    ldpc_init(&ldpc, &size_common);
//    fprintf(stderr, "ldpc needs %d bytes of shared memory\n", size_common);
//    common_array = malloc(size_common);

    testframes = 1;
    total_iters = 0;

    if (testframes) {
        uint16_t r[data_bits_per_frame];
        ofdm_rand(r, data_bits_per_frame);

        for(i=0; i<data_bits_per_frame; i++) {
            ibits[i] = r[i] > 16384;
        }
        encode(&ldpc, ibits, pbits);  
        Tbits = Terrs = Tbits_raw = Terrs_raw = 0;
    }

    fin = fopen("stm_in.raw", "rb");
    if (fin == NULL) {
        /* test mode --------------------------------------------------------*/

        fprintf(stderr, "Starting test using pre-compiled test data .....\n");
        fprintf(stderr, "Codeword length: %d\n",  CodeLength);
        fprintf(stderr, "Parity Bits....: %d\n",  NumberParityBits);

        num_runs = 1; num_ok = 0;

        for(r=0; r<num_runs; r++) {

            fprintf(stderr, "Run %d\n", r);

            PROFILE_SAMPLE(ldpc_decode);
            run_ldpc_decoder(&ldpc, out_char, ainput, &parityCheckCount);
            PROFILE_SAMPLE_AND_LOG2(ldpc_decode, "ldpc_decode");
            //fprintf(stderr, "iter: %d\n", iter);
            total_iters += iter;

            int ok = 0;
            for (i=0; i<CodeLength; i++) {
                if (out_char[i] == adetected_data[i])                    
                    ok++;
            }

            if (ok == CodeLength)
                num_ok++;            
        }

        fprintf(stderr, "test runs......: %d\n",  num_runs);
        fprintf(stderr, "test runs OK...: %d\n",  num_ok);
        if (num_runs == num_ok)
            fprintf(stderr, "test runs OK...: PASS\n");
        else
            fprintf(stderr, "test runs OK...: FAIL\n");
    }
    else {
        /* File I/O mode ------------------------------------------------*/

        int   nread, offset, frame;

        fout = fopen("stm_out.raw", "wb");
        if (fout == NULL) {
            fprintf(stderr, "Error opening output file\n");
            exit(1);
        }

        state = 0; 
        frame = 0;

        double *input_double = calloc(CodeLength, sizeof(double));
        float  *input_float  = calloc(CodeLength, sizeof(float));

        nread = CodeLength;
        offset = 0;
        fprintf(stderr, "CodeLength: %d offset: %d\n", CodeLength, offset);

        while(fread(&input_double[offset], sizeof(double), nread, fin) == nread) {
           if (testframes) {
                char in_char;
                for (i=0; i<data_bits_per_frame; i++) {
                    in_char = input_double[i] < 0;
                    if (in_char != ibits[i]) {
                        Terrs_raw++;
                    }
                    Tbits_raw++;
                }
                for (i=0; i<NumberParityBits; i++) {
                    in_char = input_double[i+data_bits_per_frame] < 0;
                    if (in_char != pbits[i]) {
                        Terrs_raw++;
                    }
                    Tbits_raw++;
                }
            }
            sd_to_llr(input_float, input_double, CodeLength);

            PROFILE_SAMPLE(ldpc_decode);
            iter = run_ldpc_decoder(&ldpc, out_char, input_float, &parityCheckCount);
            PROFILE_SAMPLE_AND_LOG2(ldpc_decode, "ldpc_decode");
            //fprintf(stderr, "iter: %d\n", iter);
            total_iters += iter;

            // Output all data packets, based on initial FEC sync
            // estimate.  Useful for testing with cohpsk_put_bits,
            // as it maintains sync with test bits state machine.
                
            next_state = state;
            switch(state) {
            case 0:
                if (iter < ldpc.max_iter) {
                    /* OK we've found which frame to sync on */
                    next_state = 1;
                    frame = 0;
                }
                break;
            case 1:
                frame++;
                if ((frame % 2) == 0) {
                    /* write decoded packets every second input frame */
                    fwrite(out_char, sizeof(char), ldpc.NumberRowsHcols, fout);
                }
                break;
            }
            state = next_state;
            //fprintf(stderr, "state: %d iter: %d\n", state, iter);

            for(i=0; i<offset; i++) {
                input_float[i] = input_float[i+offset];
            }

            if (testframes) {
                for (i=0; i<data_bits_per_frame; i++) {
                    if (out_char[i] != ibits[i]) {
                        Terrs++;
                        //fprintf(stderr, "%d %d %d\n", i, out_char[i], ibits[i]);
                    }
                    Tbits++;
                }
            }
        }

        fclose(fout);
    }  

//    ldpc_free_mem(&ldpc);

    if (fin  != NULL) fclose(fin);

    fprintf(stderr, "total iters %d\n", total_iters);
    
    if (testframes) {
        fprintf(stderr, "Raw Tbits..: %d Terr: %d BER: %4.3f\n", 
                Tbits_raw, Terrs_raw, (double)(Terrs_raw/(Tbits_raw+1E-12)));
        fprintf(stderr, "Coded Tbits: %d Terr: %d BER: %4.3f\n", 
                Tbits, Terrs, (double)(Terrs/(Tbits+1E-12)));
    }
        
    printf("\nStart Profile Data\n");
    machdep_profile_print_logged_samples();
    printf("End Profile Data\n");

    fclose(stdout);
    fclose(stderr);

    return 0;
}

/* vi:set ts=4 et sts=4: */
