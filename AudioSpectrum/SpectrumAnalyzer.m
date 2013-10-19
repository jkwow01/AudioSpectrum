#import "SpectrumAnalyzer.h"

// Octave band type definition

static Float32 middleFrequenciesForBands[][32] = {
    { 125.0f, 500, 1000, 2000 },
    { 250.0f, 400, 600, 800 },
    { 63.0f, 125, 500, 1000, 2000, 4000, 6000, 8000 },
    { 31.5f, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000 },
    { 25.0f, 31.5f, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000 },
    { 20.0f, 25, 31.5f, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000 }
};

static Float32 bandwidthForBands[] = {
    1.414f, // 2^(1/2)
    1.260f, // 2^(1/3)
    1.414f, // 2^(1/2)
    1.414f, // 2^(1/2)
    1.122f, // 2^(1/6)
    1.122f  // 2^(1/6)
};

@implementation SpectrumAnalyzer

#pragma mark Constructor / Destructor

- (id)init
{
    self = [super init];
    if (self) {
        _bandLevels = calloc(32, sizeof(Float32));
        self.pointNumber = 1024;
        self.bandType = 3;
    }
    return self;
}

- (void)dealloc
{
    self.pointNumber = 0;
    free(_bandLevels);
}

#pragma mark Custom accessors

- (void)setPointNumber:(NSUInteger)number
{
    // No need to update.
    if (_pointNumber == number) return;
    
    // Free the objects if already initialized.
    if (_pointNumber != 0) {
        vDSP_destroy_fftsetup(_fftSetup);
        free(_fftBuffer.realp);
        free(_fftBuffer.imagp);
        free(_window);
        free(_spectrum);
    }

    // Update the number.
    _pointNumber = number;
    _logPointNumber = log2(number);
    
    if (number > 0) {
        // Allocate the objects and the arrays.
        _fftSetup = vDSP_create_fftsetup(_logPointNumber, FFT_RADIX2);
        
        _fftBuffer.realp = calloc(_pointNumber / 2, sizeof(Float32));
        _fftBuffer.imagp = calloc(_pointNumber / 2, sizeof(Float32));
        
        _window = calloc(_pointNumber, sizeof(Float32));
        vDSP_blkman_window(_window, number, 0);
        
        _spectrum = calloc(_pointNumber / 2, sizeof(Float32));
    }
}

- (NSUInteger)bandCount
{
    for (NSUInteger i = 0;; i++) {
        if (middleFrequenciesForBands[_bandType][i] == 0) return i;
    }
}

#pragma mark Calculation

- (void)calculateWithAudioInputBuffer:(AudioInputBuffer *)buffer
{
    // Retrieve the waveform.
    [buffer splitEvenTo:_fftBuffer.realp oddTo:_fftBuffer.imagp totalLength:_pointNumber];
    
    // Apply the window function.
    vDSP_vmul(_fftBuffer.realp, 1, _window, 2, _fftBuffer.realp, 1, _pointNumber / 2);
    vDSP_vmul(_fftBuffer.imagp, 1, _window + 1, 2, _fftBuffer.imagp, 1, _pointNumber / 2);
    
    // FFT.
    vDSP_fft_zrip(_fftSetup, &_fftBuffer, 1, _logPointNumber, FFT_FORWARD);
    
    // Calculate the power spectrum.
    vDSP_zvmags(&_fftBuffer, 1, _spectrum, 1, _pointNumber / 2);
    
    // Calculate the band levels.
    NSUInteger bandCount = self.bandCount;
    Float32 bandWidth = bandwidthForBands[_bandType];
    
    for (NSUInteger band = 0; band < bandCount; band++) {
        NSUInteger sidxLo = floorf(middleFrequenciesForBands[_bandType][band] / bandWidth / 44100 * _pointNumber);
        NSUInteger sidxHi = floorf(middleFrequenciesForBands[_bandType][band] * bandWidth / 44100 * _pointNumber);
        
        sidxLo = MIN(MAX(sidxLo, 0), _pointNumber / 2 - 1);
        sidxHi = MIN(MAX(sidxLo, 0), _pointNumber / 2 - 1);
        
        Float32 maxLevel = 0.0f;
        for (NSUInteger i = sidxLo; i <= sidxHi; i++) {
            maxLevel = MAX(maxLevel, _spectrum[i]);
        }
        
        _bandLevels[band] = maxLevel;
    }
}

#pragma mark Static method

+ (SpectrumAnalyzer *)sharedInstance
{
    static SpectrumAnalyzer *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SpectrumAnalyzer alloc] init];
    });
    return instance;
}

@end
