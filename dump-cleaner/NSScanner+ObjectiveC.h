//
//  NSScanner+ObjectiveC.h
//  dump-cleaner
//
//  Created by Tanner on 7/29/16.
//  Copyright © 2016 Tanner Bennett. All rights reserved.
//

#import <Foundation/Foundation.h>

@class DCVariable, DCProperty, DCMethod, DCClass, DCProtocol, DCInterface;
typedef void(^InterfaceBodyBlock)(NSArray<DCProperty*> *properties, NSArray<DCMethod*> *methods);

@interface NSScanner (ObjectiveC)

#pragma mark Objective-C things
- (BOOL)scanInterface:(DCInterface **)output;
- (BOOL)scanProperty:(DCProperty **)output;
- (BOOL)scanMethod:(DCMethod **)output;
- (BOOL)scanClassOrProtocolForwardDeclaration:(NSString **)output;
- (BOOL)scanObjectType:(NSString **)output;
/// Scans starting at where methods and properties can be defined to the @end tag.
- (BOOL)scanInterfaceBody:(InterfaceBodyBlock)callback isProtocol:(BOOL)isProtocol;
/// Scans from the start of a protocol conformance list to the end.
- (BOOL)scanProtocolConformanceList:(NSArray<NSString*> **)output;
/// Scans from the opening brace of an instance variable declaration to the closing brace.
- (BOOL)scanInstanceVariableList:(NSArray<DCVariable*> **)output;
- (BOOL)scanSelector:(NSString **)output;

#pragma mark C types
- (BOOL)scanIgnoredThing;
- (BOOL)scanVariable:(DCVariable **)output;
- (BOOL)scanTypedefStructUnionOrEnum:(NSString **)output;
- (BOOL)scanStructOrUnion:(NSString **)output;
- (BOOL)scanEnum:(NSString **)output;
- (BOOL)scanBitfield:(NSString **)output;

#pragma mark Basics
- (BOOL)scanIdentifier:(NSString **)output;
- (BOOL)scanTypeMemoryQualifier:(NSString **)output;
- (BOOL)scanTypeQualifier:(NSString **)output;
- (BOOL)scanProtocolQualifier:(NSString **)output;
- (BOOL)scanType:(NSString **)output;
- (BOOL)scanPointers:(NSString **)output;
- (BOOL)scanPastSpecialMultilineCommentOrMacro;
- (BOOL)scanPastClangAttribute;

@end
