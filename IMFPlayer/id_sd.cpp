#include "id_sd.h"
//#include "fmopl.h"
#include "dbopl.h"
#include <SDL/SDL.h>
#include <string>

typedef uint8_t byte;
typedef uint16_t word;
typedef int32_t fixed;
typedef uint32_t longword;
typedef int8_t boolean;
typedef void * memptr;

//      Internal variables
static  word                    SoundPriority;


//      AdLib variables
static  byte * volatile         alSound;
static  byte                    alBlock;
static  longword                alLengthLeft;
static  longword                alTimeCount;

//      Sequencer variables
static  volatile boolean        sqActive;
static  word                   *sqHack;
static  word                   *sqHackPtr;
static  int                     sqHackLen;
static  int                     sqHackSeqLen;
static  longword                sqHackTime;

int numreadysamples = 0;
byte *curAlSound = 0;
byte *curAlSoundPtr = 0;
longword curAlLengthLeft = 0;
int soundTimeCounter = 5;
int samplesPerMusicTick;

static Chip opl_chip;

static int32_t *mix_buffer = NULL;

void OPLUpdate(Sint16 *buffer, int length)
{
	Chip__GenerateBlock2(&opl_chip, length, mix_buffer );

    // Mix into the destination buffer, doubling up into stereo.
    for (int i=0; i<length; ++i)
    {
        buffer[i * 2] = (int16_t) mix_buffer[i];
        buffer[i * 2 + 1] = (int16_t) mix_buffer[i];
    }
}


void SDL_IMFMusicPlayer(void *udata, Uint8 *stream, int len)
{
    int stereolen = len>>1;
    int sampleslen = stereolen>>1;
    Sint16 *stream16 = (Sint16 *) (void *) stream;    // expect correct alignment

    while(1)
    {
        if(numreadysamples)
        {
            if(numreadysamples<sampleslen)
            {
            	OPLUpdate(stream16, numreadysamples);
                stream16 += numreadysamples*2;
                sampleslen -= numreadysamples;
            }
            else
            {
            	OPLUpdate(stream16, sampleslen);
                numreadysamples -= sampleslen;
                return;
            }
        }
        soundTimeCounter--;
        if(!soundTimeCounter)
        {
            soundTimeCounter = 5;
            if(curAlSound != alSound)
            {
                curAlSound = curAlSoundPtr = alSound;
                curAlLengthLeft = alLengthLeft;
            }
            if(curAlSound)
            {
                if(*curAlSoundPtr)
                {
                	Chip__WriteReg(&opl_chip, alFreqL, *curAlSoundPtr );
                	Chip__WriteReg(&opl_chip, alFreqH, alBlock );
                }
                else Chip__WriteReg(&opl_chip, alFreqH, 0 );

                curAlSoundPtr++;
                curAlLengthLeft--;
                if(!curAlLengthLeft)
                {
                    curAlSound = alSound = 0;
                    SoundPriority = 0;
                	Chip__WriteReg(&opl_chip, alFreqH, 0 );
                }
            }
        }
        if(sqActive)
        {
            do
            {
                if(sqHackTime > alTimeCount) break;
                sqHackTime = alTimeCount + *(sqHackPtr+1);
            	Chip__WriteReg(&opl_chip, *(byte *) sqHackPtr, *(((byte *) sqHackPtr)+1) );
                sqHackPtr += 2;
                sqHackLen -= 4;
            }
            while(sqHackLen>0);
            alTimeCount++;
            if(!sqHackLen)
            {
                sqHackPtr = sqHack;
                sqHackLen = sqHackSeqLen;
                sqHackTime = 0;
                alTimeCount = 0;
            }
        }
        numreadysamples = samplesPerMusicTick;
    }

    SDL_MixAudio(stream, 0, len, SDL_MIX_MAXVOLUME);
}

///////////////////////////////////////////////////////////////////////////
//
//      SD_Startup() - starts up the Sound Mgr
//              Detects all additional sound hardware and installs my ISR
//
///////////////////////////////////////////////////////////////////////////
void
SD_Startup(int imf_clock_rate, int mixer_rate, int opl_rate)
{
    // Open the audio device
    SDL_AudioSpec *desired, *obtained;

    // Allocate a desired SDL_AudioSpec
    desired = (SDL_AudioSpec*) malloc(sizeof(SDL_AudioSpec));
    obtained = (SDL_AudioSpec*) malloc(sizeof(SDL_AudioSpec));
    desired->freq=mixer_rate;
    desired->format=AUDIO_S16SYS;
    desired->channels=2;
    desired->samples = (mixer_rate * 2048) / 44100;
    desired->callback=SDL_IMFMusicPlayer;
    desired->userdata=NULL;

    // Open the audio device
    if ( SDL_OpenAudio(desired, obtained) < 0 ){
      fprintf(stderr, "Couldn't open audio: %s\n", SDL_GetError());
      return;
    }

    // desired spec is no longer needed
    free(desired);

    // Init music

    samplesPerMusicTick = mixer_rate / imf_clock_rate;    // SDL_t0FastAsmService played at imf_clock_rate Hz

    mix_buffer = (int32_t *) malloc(mixer_rate * sizeof(uint32_t));

    DBOPL_InitTables();
    Chip__Chip(&opl_chip);
    Chip__Setup(&opl_chip, mixer_rate);

    SDL_PauseAudio(0);
    alTimeCount = 0;
}

///////////////////////////////////////////////////////////////////////////
//
//      SD_StartMusic() - starts playing the music pointed to
//
///////////////////////////////////////////////////////////////////////////
void
SD_StartMusic(const std::string& filename)
{
    // Load the IMF File here!
    FILE *fp=fopen(filename.c_str(), "rb");

    Uint16 size;

    fread(&size,sizeof(Uint16),1,fp);
    if (size == 0) // Is the IMF file of Type-0?
    {
        fseek(fp, 0L, SEEK_END);
        size = ftell(fp);
        fseek(fp, 0L, SEEK_SET);
    }

    byte* IMFBuffer = (byte*) malloc(size);

    fread(IMFBuffer,sizeof(byte),size,fp);

    fclose(fp);

    sqHack = (word *)(void *) IMFBuffer;

    sqHackLen = sqHackSeqLen = size;
    sqHackPtr = sqHack;
    sqHackTime = 0;
    alTimeCount = 0;

    sqActive = true;
}

///////////////////////////////////////////////////////////////////////////
//
//      SD_Shutdown() - shuts down the Sound Mgr
//              Removes sound ISR and turns off whatever sound hardware was active
//
///////////////////////////////////////////////////////////////////////////
void
SD_Shutdown(void)
{
	if(mix_buffer)
		free(mix_buffer);

	if(sqHack)
		free(sqHack);
}
