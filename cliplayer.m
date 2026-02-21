#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <editline/readline.h>

@interface CLIPlayer : NSObject
@property (nonatomic, strong) AVAudioPlayer *player;
@property (nonatomic, strong) NSString *currentDir;
@property (nonatomic, strong) NSArray *playlist;
@property (nonatomic, assign) NSInteger currentIndex;

- (void)run;
@end

@implementation CLIPlayer

- (instancetype)init {
    self = [super init];
    if (self) {
        self.currentDir = [[NSFileManager defaultManager] currentDirectoryPath];
        [self loadPlaylist];
    }
    return self;
}

- (void)loadPlaylist {
    NSError *error;
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.currentDir error:&error];
    
    // Filter only audio files
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"self ENDSWITH '.mp3' OR self ENDSWITH '.wav' OR self ENDSWITH '.m4a'"];
    self.playlist = [files filteredArrayUsingPredicate:predicate];
    self.currentIndex = -1;
}

- (void)playIndex:(NSInteger)index {
    if (index < 0 || index >= self.playlist.count) {
        printf("Invalid track index. Type 'ls' to see the playlist.\n");
        return;
    }
    
    // BUG FIX: Stop the current player before starting a new one!
    if (self.player) {
        [self.player stop];
        self.player = nil;
    }
    
    NSString *filePath = [self.currentDir stringByAppendingPathComponent:self.playlist[index]];
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];
    
    NSError *error;
    self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:fileURL error:&error];
    if (self.player) {
        [self.player play];
        self.currentIndex = index;
        printf("Playing: %s\n", [self.playlist[index] UTF8String]);
    } else {
        printf("Failed to play track: %s\n", [[error localizedDescription] UTF8String]);
    }
}

- (void)printHelp {
    printf("\n--- CLI Player Commands ---\n");
    printf("ls            : Show audio files in the current directory\n");
    printf("cd <dir>      : Change directory (e.g., cd Music, cd ..)\n");
    printf("play <number> : Play track by number from 'ls' (e.g., play 0)\n");
    printf("play          : Resume a paused track\n");
    printf("pause         : Pause the current track\n");
    printf("next          : Play the next track\n");
    printf("prev          : Play the previous track\n");
    printf("seek <sec>    : Jump to a specific second (e.g., seek 60)\n");
    printf("vol <0-100>   : Set macOS system volume (e.g., vol 50)\n");
    printf("status        : Show current playback status and time\n");
    printf("clear         : Clear the terminal screen\n");
    printf("help          : Show this help menu\n");
    printf("quit / exit   : Exit the application\n");
    printf("---------------------------\n\n");
}

- (void)run {
    // Start with a clean prompt
    while (1) {
        char *input = readline("cliplayer> ");
        if (!input) break; // Handle Ctrl+D gracefully
        
        NSString *commandLine = [[NSString stringWithUTF8String:input] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        // Add to history so UP/DOWN arrow keys work
        if (commandLine.length > 0) {
            add_history(input);
        }
        free(input); 
        
        if (commandLine.length == 0) continue;
        
        NSArray *args = [commandLine componentsSeparatedByString:@" "];
        NSString *cmd = [args[0] lowercaseString];
        
        // --- COMMAND LOGIC ---
        if ([cmd isEqualToString:@"exit"] || [cmd isEqualToString:@"quit"]) {
            if (self.player) [self.player stop];
            break;
            
        } else if ([cmd isEqualToString:@"help"]) {
            [self printHelp];
            
        } else if ([cmd isEqualToString:@"clear"]) {
            printf("\e[1;1H\e[2J");
            
        } else if ([cmd isEqualToString:@"ls"]) {
            [self loadPlaylist];
            if (self.playlist.count == 0) {
                printf("No audio files (.mp3, .wav, .m4a) found in this directory.\n");
            } else {
                for (int i = 0; i < self.playlist.count; i++) {
                    printf("[%d] %s\n", i, [self.playlist[i] UTF8String]);
                }
            }
            
        } else if ([cmd isEqualToString:@"cd"]) {
            if (args.count > 1) {
                NSString *newDir = [commandLine substringFromIndex:3];
                NSString *fullPath;
                if ([newDir isEqualToString:@".."]) {
                    fullPath = [self.currentDir stringByDeletingLastPathComponent];
                } else if ([newDir hasPrefix:@"/"]) {
                    fullPath = newDir;
                } else {
                    fullPath = [self.currentDir stringByAppendingPathComponent:newDir];
                }
                
                BOOL isDir;
                if ([[NSFileManager defaultManager] fileExistsAtPath:fullPath isDirectory:&isDir] && isDir) {
                    self.currentDir = fullPath;
                    [[NSFileManager defaultManager] changeCurrentDirectoryPath:self.currentDir];
                    [self loadPlaylist];
                    printf("Directory: %s\n", [self.currentDir UTF8String]);
                } else {
                    printf("Directory not found.\n");
                }
            }
            
        } else if ([cmd isEqualToString:@"play"]) {
            if (args.count > 1) {
                NSInteger idx = [args[1] integerValue];
                [self playIndex:idx];
            } else {
                if (self.player && !self.player.isPlaying) {
                    [self.player play];
                    printf("Track resumed.\n");
                } else if (!self.player) {
                    printf("Usage: play <number>\n");
                }
            }
            
        } else if ([cmd isEqualToString:@"pause"]) {
            if (self.player && self.player.isPlaying) {
                [self.player pause];
                printf("Track paused.\n");
            } else {
                printf("No track is currently playing.\n");
            }
            
        } else if ([cmd isEqualToString:@"next"]) {
            if (self.playlist.count > 0) {
                NSInteger nextIdx = (self.currentIndex + 1) % self.playlist.count;
                [self playIndex:nextIdx];
            } else {
                printf("Playlist is empty.\n");
            }
            
        } else if ([cmd isEqualToString:@"prev"]) {
            if (self.playlist.count > 0) {
                NSInteger prevIdx = self.currentIndex - 1;
                if (prevIdx < 0) prevIdx = self.playlist.count - 1;
                [self playIndex:prevIdx];
            } else {
                printf("Playlist is empty.\n");
            }
            
        } else if ([cmd isEqualToString:@"seek"]) {
            if (args.count > 1 && self.player) {
                NSTimeInterval time = [args[1] doubleValue];
                if (time >= 0 && time <= self.player.duration) {
                    self.player.currentTime = time;
                    printf("Jumped to %.0f seconds.\n", time);
                } else {
                    printf("Invalid time. Total duration of this track: %.0f seconds.\n", self.player.duration);
                }
            } else if (!self.player) {
                printf("No track is currently loaded.\n");
            } else {
                printf("Usage: seek <seconds>\n");
            }
            
        } else if ([cmd isEqualToString:@"vol"]) {
            if (args.count > 1) {
                int v = [args[1] intValue];
                if (v >= 0 && v <= 100) {
                    char scriptCmd[128];
                    snprintf(scriptCmd, sizeof(scriptCmd), "osascript -e 'set volume output volume %d'", v);
                    system(scriptCmd);
                    printf("System volume set to %d%%\n", v);
                } else {
                    printf("Please use a value between 0 and 100.\n");
                }
            } else {
                printf("Usage: vol <0-100>\n");
            }
            
        } else if ([cmd isEqualToString:@"status"]) {
            if (self.player) {
                int currMin = (int)self.player.currentTime / 60;
                int currSec = (int)self.player.currentTime % 60;
                int durMin = (int)self.player.duration / 60;
                int durSec = (int)self.player.duration % 60;
                
                printf("Status : %s\n", self.player.isPlaying ? "PLAYING" : "PAUSED");
                printf("Time   : %02d:%02d / %02d:%02d\n", currMin, currSec, durMin, durSec);
            } else {
                printf("No track is currently loaded.\n");
            }
            
        } else {
            printf("Command not recognized. Type 'help' for the list of commands.\n");
        }
    }
}
@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        CLIPlayer *app = [[CLIPlayer alloc] init];
        [app run];
    }
    return 0;
}