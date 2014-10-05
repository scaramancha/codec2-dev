% test_dsss.m
% David Rowe Oct 2014
%

% Simulation to test FDM QPSK combined with DSSS.  A low rate Codec
% (e.g. 450 bit/s) is transmitted on Nc=4 FDM carriers.  This same
% information is repeated Nchip=4 times on bocks of carriers that are
% delayed by up to Rs symbols.  It's like spread spectrum with a
% spreading code of 1111.  Turns out this goes a long way to
% converting a fading channel into an AWGN one.  Good scatter diagram
% and BER curve results.  Disadvantage is more bandwidth is required.

% When output error files used to simulate codec provided a few dB
% drop to 1dB SNR for intelligable speech for 450 codec combined with
% DSSS compared with legacy 1600 bit/s mode that has FEC.  Improvement
% not as great as hoped as 1600 codec can cope with higher BER.
  
1;

% main test function 

function sim_out = ber_test(sim_in, modulation)
    Fs = 8000;

    verbose          = sim_in.verbose;
    framesize        = sim_in.framesize;
    Ntrials          = sim_in.Ntrials;
    Esvec            = sim_in.Esvec;
    phase_offset     = sim_in.phase_offset;
    w_offset         = sim_in.w_offset;
    plot_scatter     = sim_in.plot_scatter;
    Rs               = sim_in.Rs;
    hf_sim           = sim_in.hf_sim;
    nhfdelay         = sim_in.hf_delay_ms*Rs/1000;
    hf_mag_only      = sim_in.hf_mag_only;
    Nchip            = sim_in.Nchip;

    bps              = 2;
    Nc = Nsymb       = framesize/bps;
    prev_sym_tx      = qpsk_mod([0 0])*ones(1,Nc*Nchip);
    prev_sym_rx      = qpsk_mod([0 0])*ones(1,Nc*Nchip);

    tx_bits_buf = zeros(1,2*framesize);
    rx_bits_buf = zeros(1,2*framesize);
    rx_symb_buf = zeros(1,2*Nsymb);

    % Init HF channel model from stored sample files of spreading signal ----------------------------------

    % convert "spreading" samples from 1kHz carrier at Fs to complex
    % baseband, generated by passing a 1kHz sine wave through PathSim
    % with the ccir-poor model, enabling one path at a time.
    
    Fc = 1000; M = Fs/Rs;
    fspread = fopen("../raw/sine1k_2Hz_spread.raw","rb");
    spread1k = fread(fspread, "int16")/10000;
    fclose(fspread);
    fspread = fopen("../raw/sine1k_2ms_delay_2Hz_spread.raw","rb");
    spread1k_2ms = fread(fspread, "int16")/10000;
    fclose(fspread);

    % down convert to complex baseband
    spreadbb = spread1k.*exp(-j*(2*pi*Fc/Fs)*(1:length(spread1k))');
    spreadbb_2ms = spread1k_2ms.*exp(-j*(2*pi*Fc/Fs)*(1:length(spread1k_2ms))');

    % remove -2000 Hz image
    b = fir1(50, 5/Fs);
    spread = filter(b,1,spreadbb);
    spread_2ms = filter(b,1,spreadbb_2ms);
   
    % discard first 1000 samples as these were near 0, probably as
    % PathSim states were ramping up

    spread    = spread(1000:length(spread));
    spread_2ms = spread_2ms(1000:length(spread_2ms));

    % decimate down to Rs

    spread = spread(1:M:length(spread));
    spread_2ms = spread_2ms(1:M:length(spread_2ms));

    % Determine "gain" of HF channel model, so we can normalise
    % carrier power during HF channel sim to calibrate SNR.  I imagine
    % different implementations of ccir-poor would do this in
    % different ways, leading to different BER results.  Oh Well!

    hf_gain = 1.0/sqrt(var(spread)+var(spread_2ms));

    % Start Simulation ----------------------------------------------------------------

    for ne = 1:length(Esvec)
        EsNodB = Esvec(ne);
        EsNo = 10^(EsNodB/10);
    
        variance = 1/EsNo;
         if verbose > 1
            printf("EsNo (dB): %f EsNo: %f variance: %f\n", EsNodB, EsNo, variance);
        end
        
        Terrs = 0;  Tbits = 0;

        tx_symb_log      = [];
        rx_symb_log      = [];
        noise_log        = [];
        errors_log       = [];
        Nerrs_log        = [];

        % init HF channel

        hf_n = 1;

        % simulation starts here-----------------------------------
 
        for nn = 1: Ntrials
                  
            tx_bits = round( rand( 1, framesize) );                       

            % modulate --------------------------------------------

            tx_symb=zeros(1,Nc*Nchip);

            for i=1:Nc
                tx_symb(i) = qpsk_mod(tx_bits(2*(i-1)+1:2*i));
            end

            % Optionally copy to other carriers (spreading)

            for i=Nc+1:Nc:Nc*Nchip
                tx_symb(i:i+Nc-1) = tx_symb(1:Nc);
            end
 
            % Optionally DQPSK encode
 
            if strcmp(modulation,'dqpsk')
              for i=1:Nc*Nchip
                tx_symb(i) *= prev_sym_tx(i);
                prev_sym_tx(i) = tx_symb(i);
              end 
            end

            s_ch = tx_symb/sqrt(Nchip);

            % HF channel simulation  ------------------------------------
            
            if hf_sim

                % separation between carriers.  Note this effectively
                % under samples at Rs, I dont think this matters.
                % Equivalent to doing freq shift at Fs, then
                % decimating to Rs.

                wsep = 2*pi*(1+0.5);  % e.g. 75Hz spacing at Rs=50Hz, alpha=0.5 filters

                hf_model(hf_n, :) = zeros(1,Nc);

                for i=1:Nchip
                    time_shift = floor(i*Rs/4);
                    for k=1:Nc
                        ahf_model = hf_gain*(spread(hf_n+time_shift) + exp(-j*k*wsep*nhfdelay)*spread_2ms(hf_n+time_shift));
                        if hf_mag_only
                             s_ch((i-1)*Nc+k) *= abs(ahf_model);
                        else
                             s_ch((i-1)*Nc+k) *= ahf_model;
                        end
                        hf_model(hf_n, k) += ahf_model/Nchip;
                    end
                end
                hf_n++;
            end
           
            tx_symb_log = [tx_symb_log s_ch];

            % AWGN noise and phase/freq offset channel simulation
            % 0.5 factor ensures var(noise) == variance , i.e. splits power between Re & Im

            noise = sqrt(variance*0.5)*(randn(1,Nsymb*Nchip) + j*randn(1,Nsymb*Nchip));
            noise_log = [noise_log noise];

            s_ch = s_ch + noise;

            % de-modulate

            for i=1:Nc*Nchip
                rx_symb(i) = s_ch(i);
                if strcmp(modulation,'dqpsk')
                    tmp = rx_symb(i);
                    rx_symb(i) *= conj(prev_sym_rx(i)/abs(prev_sym_rx(i)));
                    prev_sym_rx(i) = tmp;
                end
            end

            % de-spread

            for i=Nc+1:Nc:Nchip*Nc
              rx_symb(1:Nc) = rx_symb(1:Nc) + rx_symb(i:i+Nc-1);
            end

            % demodulate

            rx_bits = zeros(1, framesize);
            for i=1:Nc
              rx_bits((2*(i-1)+1):(2*i)) = qpsk_demod(rx_symb(i));
            end
            rx_symb_log = [rx_symb_log rx_symb(1:Nc)];

            % Measure BER

            error_positions = xor(rx_bits, tx_bits);
            Nerrs = sum(error_positions);
            Terrs += Nerrs;
            Tbits += length(tx_bits);
            errors_log = [errors_log error_positions];
            Nerrs_log = [Nerrs_log Nerrs];
        end
    
        TERvec(ne) = Terrs;
        BERvec(ne) = Terrs/Tbits;

        if verbose 
            av_tx_pwr = (tx_symb_log * tx_symb_log')/length(tx_symb_log);

            printf("EsNo (dB): %f  Terrs: %d BER %4.2f QPSK BER theory %4.2f av_tx_pwr: %3.2f", EsNodB, Terrs,
                   Terrs/Tbits, 0.5*erfc(sqrt(EsNo/2)), av_tx_pwr);
            printf("\n");
        end
        if verbose > 1
            printf("Terrs: %d BER %f BER theory %f C %f N %f Es %f No %f Es/No %f\n\n", Terrs,
                   Terrs/Tbits, 0.5*erfc(sqrt(EsNo/2)), var(tx_symb_log), var(noise_log),
                   var(tx_symb_log), var(noise_log), var(tx_symb_log)/var(noise_log));
        end
    end
    
    Ebvec = Esvec - 10*log10(bps);
    sim_out.BERvec          = BERvec;
    sim_out.Ebvec           = Ebvec;
    sim_out.TERvec          = TERvec;
    sim_out.errors_log      = errors_log;

    if plot_scatter
        figure(2);
        clf;
        scat = rx_symb_log .* exp(j*pi/4);
        plot(real(scat), imag(scat),'+');
        title('Scatter plot');

        if hf_sim
          figure(3);
          clf;
        
          y = 1:(hf_n-1);
          x = 1:Nc;
          EsNodBSurface = 20*log10(abs(hf_model(y,:))) - 10*log10(variance);
          EsNodBSurface(find(EsNodBSurface < -5)) = -5;
          mesh(x,y,EsNodBSurface);
          grid
          axis([1 Nc 1 Rs*5 -5 15])
          title('HF Channel Es/No');

          if verbose 
            av_hf_pwr = sum(abs(hf_model(y)).^2)/(hf_n-1);
            printf("average HF power: %3.2f over %d symbols\n", av_hf_pwr, hf_n-1);
          end
        end

        figure(4)
        clf
        stem(Nerrs_log)
   end

endfunction

% Gray coded QPSK modulation function

function symbol = qpsk_mod(two_bits)
    two_bits_decimal = sum(two_bits .* [2 1]); 
    switch(two_bits_decimal)
        case (0) symbol =  1;
        case (1) symbol =  j;
        case (2) symbol = -j;
        case (3) symbol = -1;
    endswitch
endfunction

% Gray coded QPSK demodulation function

function two_bits = qpsk_demod(symbol)
    if isscalar(symbol) == 0
        printf("only works with scalars\n");
        return;
    end
    bit0 = real(symbol*exp(j*pi/4)) < 0;
    bit1 = imag(symbol*exp(j*pi/4)) < 0;
    two_bits = [bit1 bit0];
endfunction

function sim_in = standard_init
  sim_in.verbose          = 1;
  sim_in.plot_scatter     = 0;

  sim_in.Esvec            = 5; 
  sim_in.Ntrials          = 30;
  sim_in.framesize        = 8;
  sim_in.Rs               = 50;
  sim_in.Nc               = 4;

  sim_in.phase_offset     = 0;
  sim_in.w_offset         = 0;
  sim_in.phase_noise_amp  = 0;

  sim_in.hf_delay_ms      = 2;
  sim_in.hf_sim           = 0;
  sim_in.hf_mag_only      = 0;

  sim_in.Nchip            = 1;
endfunction

function test_curves

  sim_in = standard_init();

  sim_in.verbose          = 1;
  sim_in.plot_scatter     = 1;

  sim_in.Esvec            = 50; 
  sim_in.hf_sim           = 0;
  sim_in.Ntrials          = 1000;

  sim_qpsk_hf             = ber_test(sim_in, 'qpsk');

  sim_in.hf_sim           = 0;
  sim_in.plot_scatter     = 0;
  sim_in.Esvec            = 5:15; 
  Ebvec = sim_in.Esvec - 10*log10(2);
  BER_theory = 0.5*erfc(sqrt(10.^(Ebvec/10)));
  sim_dqpsk               = ber_test(sim_in, 'dqpsk');
  sim_in.hf_sim           = 1;
  sim_in.hf_mag_only      = 1;
  sim_qpsk_hf             = ber_test(sim_in, 'qpsk');
  sim_in.hf_mag_only      = 0;
  sim_dqpsk_hf            = ber_test(sim_in, 'dqpsk');
  sim_in.Nchip            = 4;
  sim_dqpsk_hf_dsss       = ber_test(sim_in, 'dqpsk');

  figure(1); 
  clf;
  semilogy(Ebvec, BER_theory,'r;QPSK theory;')
  hold on;
  semilogy(sim_dqpsk.Ebvec, sim_dqpsk.BERvec,'c;DQPSK AWGN;')
  semilogy(sim_qpsk_hf.Ebvec, sim_qpsk_hf.BERvec,'b;QPSK HF;')
  semilogy(sim_dqpsk_hf.Ebvec, sim_dqpsk_hf.BERvec,'k;DQPSK HF;')
  semilogy(sim_dqpsk_hf_dsss.Ebvec, sim_dqpsk_hf_dsss.BERvec,'g;DQPSK DSSS HF;')
  hold off;

  xlabel('Eb/N0')
  ylabel('BER')
  grid("minor")
  axis([min(Ebvec) max(Ebvec) 1E-3 1])
endfunction

function test_single

  sim_in = standard_init();

  sim_in.verbose          = 1;
  sim_in.plot_scatter     = 1;

  sim_in.Esvec            = 10; 
  sim_in.hf_sim           = 1;
  sim_in.Nchip            = 4;
  sim_in.Ntrials          = 500;
  
  sim_qpsk_hf             = ber_test(sim_in, 'dqpsk');
endfunction

function test_1600_v_450

  sim_in = standard_init();

  sim_in.verbose          = 1;
  sim_in.plot_scatter     = 1;
  sim_in.Ntrials          = 500;
  sim_in.hf_sim           = 1;

  sim_in.framesize        = 32;
  sim_in.Nc               = 16;
  sim_in.Esvec            = 7; 
  sim_in.Nchip            = 1;
  
  sim_dqpsk_hf_1600        = ber_test(sim_in, 'dqpsk');

  sim_in.framesize        = 8;
  sim_in.Nc               = 4;
  sim_in.Esvec            = sim_in.Esvec + 10*log10(1600/450); 
  sim_in.Nchip            = 4;
  
  sim_dqpsk_hf_450         = ber_test(sim_in, 'dqpsk');
  
  fep=fopen("errors_1600.bin","wb"); fwrite(fep, sim_dqpsk_hf_1600.errors_log, "short"); fclose(fep);
  fep=fopen("errors_450.bin","wb"); fwrite(fep, sim_dqpsk_hf_450.errors_log, "short"); fclose(fep);

endfunction


% Start simulations ---------------------------------------

more off;

test_1600_v_450();
test_curves();
