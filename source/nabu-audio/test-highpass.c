#include <stdio.h>
#include "highpass.c"
int main(void) {
    for (int rate = 44100; rate <= 48000; rate += 3900) {
        double frequencies[] = {50, 200, 1000};
        for (int f = 0; f < 3; ++f) {
            Highpass *h = instantiate(&descriptor, rate);
            float in[256], out[256];
            connect_port(h, 0, in); connect_port(h, 1, out);
            double energy_in=0, energy_out=0;
            for (int block=0; block<200; ++block) {
                for (int i=0; i<256; ++i)
                    in[i]=0.5*sin(2*3.141592653589793*frequencies[f]*(block*256+i)/rate);
                run(h,256);
                if (block>10) for(int i=0;i<256;++i){energy_in+=in[i]*in[i];energy_out+=out[i]*out[i];}
            }
            double db=10*log10(energy_out/energy_in);
            printf("%d Hz sample rate, %.0f Hz signal: %.3f dB\n",rate,frequencies[f],db);
            free(h);
            if (!isfinite(db) || (f==0 && db>-23) || (f==1 && fabs(db+3.0103)>0.1) || (f==2 && fabs(db)>0.1)) return 1;
        }
    }
    return 0;
}
