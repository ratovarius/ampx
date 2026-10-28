#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const AmpXTagFileErrorDomain;

typedef NS_ERROR_ENUM(AmpXTagFileErrorDomain, AmpXTagFileError) {
    AmpXTagFileErrorUnsupported = 1,
    AmpXTagFileErrorUnreadable = 2,
    AmpXTagFileErrorSaveFailed = 3,
};

/// DJ mode's standard tag fields through TagLib (DJ mode spec Revision 2 § Tag writing). Keys: bpm, key, label,
/// remixer, composer, grouping. Containers by extension: mp3, wav, aif/aiff (ID3v2), flac (Xiph comment),
/// m4a/mp4 (iTunes items). Writes touch only the given fields.
@interface AmpXTagFile : NSObject

+ (nullable NSDictionary<NSString *, NSString *> *)readFieldsAtPath:(NSString *)path error:(NSError **)error;
+ (BOOL)writeFields:(NSDictionary<NSString *, NSString *> *)fields toPath:(NSString *)path error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
