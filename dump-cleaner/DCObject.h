//
//  DCObject.h
//  dump-cleaner
//
//  Created by Tanner on 3/20/16.
//  Copyright © 2016 Tanner Bennett. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface DCObject : NSObject {
@protected
    NSString *_string;
}

/// Subclasses should not override
+ (instancetype)withString:(NSString *)string;
/// Subclasses should implement, no call to super
- (id)initWithString:(NSString *)string;
/// Subclasses should override for testing
+ (BOOL)test;

/// Subclasses should override backed value to return the desired result
@property (nonatomic, readonly) NSString *string;

@end
