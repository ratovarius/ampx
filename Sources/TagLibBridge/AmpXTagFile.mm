#import "AmpXTagFile.h"

#include <map>
#include <set>
#include <string>

#include "aifffile.h"
#include "flacfile.h"
#include "id3v2tag.h"
#include "mp4file.h"
#include "mp4tag.h"
#include "mpegfile.h"
#include "textidentificationframe.h"
#include "wavfile.h"
#include "xiphcomment.h"

NSErrorDomain const AmpXTagFileErrorDomain = @"AmpXTagFile";

namespace {

enum class Container { id3MPEG, id3WAV, id3AIFF, flac, mp4, unsupported };

struct FieldNames {
    const char *id3;
    const char *xiph;
    const char *mp4;
};

/// Field → frame / comment / item, per the spec's table. TagLib reads these as Latin-1, so © is octal 251.
const std::map<std::string, FieldNames> &fieldNames() {
    static const std::map<std::string, FieldNames> names = {
        {"bpm", {"TBPM", "BPM", "tmpo"}},
        {"key", {"TKEY", "INITIALKEY", "----:com.apple.iTunes:initialkey"}},
        {"label", {"TPUB", "LABEL", "----:com.apple.iTunes:LABEL"}},
        {"remixer", {"TPE4", "REMIXER", "----:com.apple.iTunes:REMIXER"}},
        {"composer", {"TCOM", "COMPOSER", "\251wrt"}},
        {"grouping", {"TIT1", "GROUPING", "\251grp"}},
    };
    return names;
}

Container containerFor(NSString *path) {
    NSString *ext = path.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"mp3"]) return Container::id3MPEG;
    if ([ext isEqualToString:@"wav"]) return Container::id3WAV;
    if ([ext isEqualToString:@"aif"] || [ext isEqualToString:@"aiff"]) return Container::id3AIFF;
    if ([ext isEqualToString:@"flac"]) return Container::flac;
    if ([ext isEqualToString:@"m4a"] || [ext isEqualToString:@"mp4"]) return Container::mp4;
    return Container::unsupported;
}

NSString *toNSString(const TagLib::String &value) {
    return [NSString stringWithUTF8String:value.toCString(true)];
}

TagLib::String toTagString(NSString *value) {
    return TagLib::String(value.UTF8String, TagLib::String::UTF8);
}

BOOL fail(NSError **error, AmpXTagFileError code, NSString *path) {
    if (error) {
        *error = [NSError errorWithDomain:AmpXTagFileErrorDomain code:code userInfo:@{NSFilePathErrorKey: path}];
    }
    return NO;
}

void readID3(TagLib::ID3v2::Tag *tag, NSMutableDictionary *fields) {
    if (!tag) return;
    for (const auto &[field, names] : fieldNames()) {
        const auto &frames = tag->frameListMap()[names.id3];
        if (!frames.isEmpty()) {
            NSString *value = toNSString(frames.front()->toString());
            if (value.length > 0) fields[@(field.c_str())] = value;
        }
    }
}

std::set<std::string> managedKeys(const char *FieldNames::*member) {
    std::set<std::string> keys;
    for (const auto &[field, names] : fieldNames()) keys.insert(names.*member);
    return keys;
}

void otherID3(TagLib::ID3v2::Tag *tag, NSMutableArray<NSString *> *keys) {
    if (!tag) return;
    const auto managed = managedKeys(&FieldNames::id3);
    for (const auto *frame : tag->frameList()) {
        std::string id(frame->frameID().data(), frame->frameID().size());
        if (!managed.count(id)) [keys addObject:@(id.c_str())];
    }
}

void writeID3(TagLib::ID3v2::Tag *tag, NSDictionary<NSString *, NSString *> *fields) {
    for (NSString *field in fields) {
        auto names = fieldNames().find(field.UTF8String);
        if (names == fieldNames().end()) continue;
        tag->removeFrames(names->second.id3);
        auto *frame = new TagLib::ID3v2::TextIdentificationFrame(names->second.id3, TagLib::String::UTF8);
        frame->setText(toTagString(fields[field]));
        tag->addFrame(frame);
    }
}

/// The ID3v2 version a file already uses; a new tag is ID3v2.4. TagLib cannot write v2.2, so a v2.2 tag becomes
/// v2.3, the closer and more widely read version.
TagLib::ID3v2::Version versionOf(TagLib::ID3v2::Tag *tag, bool hadTag) {
    if (!hadTag) return TagLib::ID3v2::v4;
    return tag->header()->majorVersion() == 4 ? TagLib::ID3v2::v4 : TagLib::ID3v2::v3;
}

}  // namespace

@implementation AmpXTagFile

+ (nullable NSArray<NSString *> *)otherKeysAtPath:(NSString *)path error:(NSError **)error {
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    const char *file = path.fileSystemRepresentation;
    switch (containerFor(path)) {
    case Container::id3MPEG: {
        TagLib::MPEG::File mpeg(file, false);
        if (!mpeg.isValid()) return fail(error, AmpXTagFileErrorUnreadable, path) ? nil : nil;
        if (mpeg.hasID3v2Tag()) otherID3(mpeg.ID3v2Tag(false), keys);
        if (mpeg.hasID3v1Tag()) [keys addObject:@"ID3v1"];
        if (mpeg.hasAPETag()) [keys addObject:@"APE"];
        break;
    }
    case Container::id3WAV: {
        TagLib::RIFF::WAV::File wav(file, false);
        if (!wav.isValid()) return fail(error, AmpXTagFileErrorUnreadable, path) ? nil : nil;
        if (wav.hasID3v2Tag()) otherID3(wav.ID3v2Tag(), keys);
        if (wav.hasInfoTag()) [keys addObject:@"INFO"];
        break;
    }
    case Container::id3AIFF: {
        TagLib::RIFF::AIFF::File aiff(file, false);
        if (!aiff.isValid()) return fail(error, AmpXTagFileErrorUnreadable, path) ? nil : nil;
        if (aiff.hasID3v2Tag()) otherID3(aiff.tag(), keys);
        break;
    }
    case Container::flac: {
        TagLib::FLAC::File flac(file, false);
        if (!flac.isValid()) return fail(error, AmpXTagFileErrorUnreadable, path) ? nil : nil;
        const auto managed = managedKeys(&FieldNames::xiph);
        if (auto *comment = flac.xiphComment(false)) {
            for (const auto &[name, values] : comment->fieldListMap()) {
                std::string key = name.to8Bit(true);
                if (managed.count(key)) continue;
                for (unsigned int i = 0; i < values.size(); i++) [keys addObject:@(key.c_str())];
            }
        }
        for (unsigned int i = 0; i < flac.pictureList().size(); i++) [keys addObject:@"PICTURE"];
        if (flac.hasID3v2Tag()) otherID3(flac.ID3v2Tag(false), keys);
        break;
    }
    case Container::mp4: {
        TagLib::MP4::File mp4(file, false);
        if (!mp4.isValid()) return fail(error, AmpXTagFileErrorUnreadable, path) ? nil : nil;
        const auto managed = managedKeys(&FieldNames::mp4);
        if (auto *tag = mp4.tag()) {
            for (const auto &[name, item] : tag->itemMap()) {
                std::string key = name.to8Bit(false);
                if (managed.count(key)) continue;
                if (key == "covr") {
                    for (unsigned int i = 0; i < item.toCoverArtList().size(); i++) [keys addObject:@"covr"];
                } else {
                    [keys addObject:@(name.to8Bit(true).c_str())];
                }
            }
        }
        break;
    }
    case Container::unsupported:
        return fail(error, AmpXTagFileErrorUnsupported, path) ? nil : nil;
    }
    return keys;
}

+ (nullable NSDictionary<NSString *, NSString *> *)readFieldsAtPath:(NSString *)path error:(NSError **)error {
    NSMutableDictionary<NSString *, NSString *> *fields = [NSMutableDictionary dictionary];
    const char *file = path.fileSystemRepresentation;
    switch (containerFor(path)) {
    case Container::id3MPEG: {
        TagLib::MPEG::File mpeg(file, false);
        if (!mpeg.isValid()) return fail(error, AmpXTagFileErrorUnreadable, path) ? nil : nil;
        readID3(mpeg.ID3v2Tag(false), fields);
        break;
    }
    case Container::id3WAV: {
        TagLib::RIFF::WAV::File wav(file, false);
        if (!wav.isValid()) return fail(error, AmpXTagFileErrorUnreadable, path) ? nil : nil;
        if (wav.hasID3v2Tag()) readID3(wav.ID3v2Tag(), fields);
        break;
    }
    case Container::id3AIFF: {
        TagLib::RIFF::AIFF::File aiff(file, false);
        if (!aiff.isValid()) return fail(error, AmpXTagFileErrorUnreadable, path) ? nil : nil;
        if (aiff.hasID3v2Tag()) readID3(aiff.tag(), fields);
        break;
    }
    case Container::flac: {
        TagLib::FLAC::File flac(file, false);
        if (!flac.isValid()) return fail(error, AmpXTagFileErrorUnreadable, path) ? nil : nil;
        if (auto *comment = flac.xiphComment(false)) {
            for (const auto &[field, names] : fieldNames()) {
                const auto &values = comment->fieldListMap()[names.xiph];
                if (!values.isEmpty() && !values.front().isEmpty()) fields[@(field.c_str())] = toNSString(values.front());
            }
        }
        break;
    }
    case Container::mp4: {
        TagLib::MP4::File mp4(file, false);
        if (!mp4.isValid()) return fail(error, AmpXTagFileErrorUnreadable, path) ? nil : nil;
        if (auto *tag = mp4.tag()) {
            for (const auto &[field, names] : fieldNames()) {
                if (!tag->contains(names.mp4)) continue;
                const auto item = tag->item(names.mp4);
                if (field == "bpm") {
                    if (item.toInt() > 0) fields[@"bpm"] = [NSString stringWithFormat:@"%d", item.toInt()];
                } else if (!item.toStringList().isEmpty() && !item.toStringList().front().isEmpty()) {
                    fields[@(field.c_str())] = toNSString(item.toStringList().front());
                }
            }
        }
        break;
    }
    case Container::unsupported:
        return fail(error, AmpXTagFileErrorUnsupported, path) ? nil : nil;
    }
    return fields;
}

+ (BOOL)writeFields:(NSDictionary<NSString *, NSString *> *)fields toPath:(NSString *)path error:(NSError **)error {
    const char *file = path.fileSystemRepresentation;
    bool saved = false;
    switch (containerFor(path)) {
    case Container::id3MPEG: {
        TagLib::MPEG::File mpeg(file, false);
        if (!mpeg.isValid()) return fail(error, AmpXTagFileErrorUnreadable, path);
        bool hadTag = mpeg.hasID3v2Tag();
        auto *tag = mpeg.ID3v2Tag(true);
        auto version = versionOf(tag, hadTag);
        writeID3(tag, fields);
        // Only the ID3v2 tag is rewritten; ID3v1 and APE tags stay as they are.
        saved = mpeg.save(TagLib::MPEG::File::ID3v2, TagLib::File::StripNone, version, TagLib::File::DoNotDuplicate);
        break;
    }
    case Container::id3WAV: {
        TagLib::RIFF::WAV::File wav(file, false);
        if (!wav.isValid()) return fail(error, AmpXTagFileErrorUnreadable, path);
        bool hadTag = wav.hasID3v2Tag();
        auto *tag = wav.ID3v2Tag();
        auto version = versionOf(tag, hadTag);
        writeID3(tag, fields);
        saved = wav.save(TagLib::RIFF::WAV::File::ID3v2, TagLib::File::StripNone, version);
        break;
    }
    case Container::id3AIFF: {
        TagLib::RIFF::AIFF::File aiff(file, false);
        if (!aiff.isValid()) return fail(error, AmpXTagFileErrorUnreadable, path);
        bool hadTag = aiff.hasID3v2Tag();
        auto *tag = aiff.tag();
        auto version = versionOf(tag, hadTag);
        writeID3(tag, fields);
        saved = aiff.save(version);
        break;
    }
    case Container::flac: {
        TagLib::FLAC::File flac(file, false);
        if (!flac.isValid()) return fail(error, AmpXTagFileErrorUnreadable, path);
        auto *comment = flac.xiphComment(true);
        for (NSString *field in fields) {
            auto names = fieldNames().find(field.UTF8String);
            if (names != fieldNames().end()) comment->addField(names->second.xiph, toTagString(fields[field]), true);
        }
        saved = flac.save();
        break;
    }
    case Container::mp4: {
        TagLib::MP4::File mp4(file, false);
        if (!mp4.isValid() || !mp4.tag()) return fail(error, AmpXTagFileErrorUnreadable, path);
        auto *tag = mp4.tag();
        for (NSString *field in fields) {
            auto names = fieldNames().find(field.UTF8String);
            if (names == fieldNames().end()) continue;
            if ([field isEqualToString:@"bpm"]) {
                tag->setItem(names->second.mp4, TagLib::MP4::Item(fields[field].intValue));
            } else {
                tag->setItem(names->second.mp4, TagLib::MP4::Item(TagLib::StringList(toTagString(fields[field]))));
            }
        }
        saved = mp4.save();
        break;
    }
    case Container::unsupported:
        return fail(error, AmpXTagFileErrorUnsupported, path);
    }
    return saved ? YES : fail(error, AmpXTagFileErrorSaveFailed, path);
}

@end
