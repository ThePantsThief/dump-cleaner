//
//  NSString+Regex.h
//  dump-cleaner
//
//  Created by Tanner Bennett on 3/13/16.
//  Copyright © 2016 Tanner Bennett. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface NSString (Regex)

@property (nonatomic, readonly) NSString *pascalCaseString;

- (BOOL)matchesPattern:(NSString *)pattern;

- (NSString *)matchGroupAtIndex:(NSUInteger)idx forRegex:(NSString *)regex;
- (NSArray<NSTextCheckingResult*> *)matchesForRegex:(NSString *)pattern;
- (NSArray<NSString*> *)allMatchesForRegex:(NSString *)regex atIndex:(NSUInteger)idx;
- (NSArray<NSValue*> *)rangesForAllMatchesForRegex:(NSString *)regex atIndex:(NSUInteger)idx;
- (NSString *)stringByReplacingMatchesForRegex:(NSString *)regex withString:(NSString *)replacement;

@end
