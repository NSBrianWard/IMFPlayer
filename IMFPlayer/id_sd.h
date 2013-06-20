//
//      ID Engine
//      ID_SD.h - Sound Manager Header
//      Version for Wolfenstein
//      By Jason Blochowiak
//

#ifndef __ID_SD__
#define __ID_SD__

#include <string>

//      Register addresses
// Operator stuff
#define alChar          0x20
#define alScale         0x40
#define alAttack        0x60
#define alSus           0x80
#define alWave          0xe0
// Channel stuff
#define alFreqL         0xa0
#define alFreqH         0xb0
#define alFeedCon       0xc0
// Global stuff
#define alEffects       0xbd



// Function prototypes
extern  void    SD_Startup(int imf_clock_rate, int mixer_rate, int opl_rate),
                SD_Shutdown(void);


extern  void    SD_StartMusic(const std::string& filename);
extern  void    SD_ContinueMusic(int chunk, int startoffs);
extern  void    SD_MusicOn(void);
extern  int     SD_MusicOff(void);

#endif
