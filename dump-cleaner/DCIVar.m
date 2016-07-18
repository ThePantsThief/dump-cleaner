//
//  DCIVar.m
//  dump-cleaner
//
//  Created by Tanner on 3/20/16.
//  Copyright © 2016 Tanner Bennett. All rights reserved.
//

#import "DCIVar.h"


@interface DCIVar ()
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *type;
@end

@implementation DCIVar

- (id)initWithString:(NSString *)string {
    self = [super init];
    if (self) {
        _name = [string allMatchesForRegex:krIvarComponents_12 atIndex:krIvarComponents_name].firstObject;
        _type = [string allMatchesForRegex:krIvarComponents_12 atIndex:krIvarComponents_type].firstObject;
        
        // Replace `Type*` with `Type *`
        // TODO stronger space enforcement (i.e. remove multiple spaces with regex)
        if ([_type hasSuffix:@"*"] && ![_type hasSuffix:@" *"]) {
            _type = [_type stringByReplacingOccurrencesOfString:@"*" withString:@" *"];
        }
        
        NSParameterAssert(_name && _type);
        
        if ([_type hasSuffix:@"*"]) {
            _string = [NSString stringWithFormat:@"    %@%@;", _type, _name];
        } else {
            _string = [NSString stringWithFormat:@"    %@ %@;", _type, _name];
        }
    }
    
    return self;
}

- (BOOL)isEqual:(id)object {
    if ([object isKindOfClass:[DCIVar class]])
        return [self isEqualToIVar:object];
    
    return [super isEqual:object];
}

- (BOOL)isEqualToIVar:(DCIVar *)ivar {
    return [self.name isEqualToString:ivar.name] && [self.type isEqualToString:ivar.type];
}

+ (BOOL)test {
    DCIVar *ivar = [DCIVar withString:@"    NSString* _name;\n"];
    DCAssertEqualObjects(@"_name", ivar.name);
    DCAssertEqualObjects(@"NSString *", ivar.type);
    
    ivar = [DCIVar withString:@"    NSArray<NSString *> *_things;\n"];
    DCAssertEqualObjects(@"_things", ivar.name);
    DCAssertEqualObjects(@"NSArray<NSString *> *", ivar.type);
    
    return YES;
}

@end
