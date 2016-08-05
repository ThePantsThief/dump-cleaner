//
//  NSScanner+ObjectiveC.m
//  dump-cleaner
//
//  Created by Tanner on 7/29/16.
//  Copyright © 2016 Tanner Bennett. All rights reserved.
//

#import "NSScanner+ObjectiveC.h"
#import "NSScanner+Helper.h"
#import "DCProperty.h"
#import "DCVariable.h"
#import "DCClass.h"
#import "DCProtocol.h"
#import "DCMethod.h"


@implementation NSScanner (ObjectiveC)

static NSMutableDictionary<NSString*, DCProtocol*> *SDKProtocols;
static NSMutableDictionary<NSString*, DCProtocol*> *dumpedProtocols;
+ (void)setExistingProtocolPools:(NSMutableDictionary<NSString *,DCProtocol *> *)SDKs
                          dumped:(NSMutableDictionary<NSString *,DCProtocol *> *)dumped {
    NSParameterAssert(SDKs); NSParameterAssert(dumped);
    SDKProtocols    = SDKs;
    dumpedProtocols = dumped;
}

#pragma mark Objective-C things

- (BOOL)parseHeader:(ParseCallbackBlock)completion {
    NSParameterAssert(self.string.length); NSParameterAssert(completion);
    
    NSMutableArray *interfaces  = [NSMutableArray array];
    NSMutableArray *structNames = [NSMutableArray array];
    DCInterface *tmp  = nil;
    NSString *structt = nil;
    BOOL didRunOnce   = NO;
    
    // Scan past comments and other crap, look for interfaces and struct/union declarations
    // Skip untypedef'd structs and unions, skip all enums and forward declarations,
    // skip all global variables.
    while ([self scanPastIgnoredThing] ||
           [self scanClassOrProtocolForwardDeclaration:nil] ||
           [self scanStructOrUnion:nil] ||
           [self scanEnum:nil] ||
           [self scanGlobalVariale:nil] ||
           [self scanInterface:&tmp] ||
           [self scanTypedefStructUnionOrEnum:&structt]) {
        didRunOnce = YES;
        
        while ([self scanPastIgnoredThing]) { }
        
        if (tmp) {
            [interfaces addObject:tmp];
            tmp = nil;
        }
        if (structt) {
            NSMutableString *name = structt.mutableCopy;
            structt = nil;
            [name replaceOccurrencesOfString:@"typedef " withString:@"" options:0 range:NSMakeRange(0, name.length)];
            if ([name hasPrefix:@"struct"]) {
                [name deleteLastCharacter];
                [structNames addObject:[name componentsSeparatedByString:@" "].lastObject];
            }
        }
    }
    
    completion(interfaces, structNames);
    return didRunOnce;
}

- (BOOL)scanInterface:(DCInterface **)output {
    ScanPush();
    
    Class cls = Nil;
    if ([self scanString:@"@interface"]) {
        cls = [DCClass class];
    } else if ([self scanString:@"@protocol"]) {
        cls = [DCProtocol class];
        
        // Check whether or not we need to skip
        // this protocol entirely.
        NSString *name = nil;
        [self scanIdentifier:&name];
        if ([SDKProtocols.allKeys containsObject:name] ||
            [dumpedProtocols.allKeys containsObject:name]) {
            ScanAssertPop([self scanToString:@"@end"]);
            return YES;
        }
    }
    
    if (cls) {
        ScanAssertPop([self scanToString:@"@end"]);
        [self scanString:@"@end"];
        DCInterface *interface = [cls withString:[self.scannedString substringFromIndex:start]];
        
        if (interface) {
            *output = interface;
            return YES;
        }
    }
    
    ScanPop();
    return NO;
}

- (BOOL)scanProperty:(DCProperty **)output {
    ScanPush();
    static NSArray *propSelectors = StaticArray(propSelectors, @"getter", @"setter")
    static NSArray *propAttrs = StaticArray(propAttrs, @"nonatomic", @"copy",
                                            @"readonly",@"assign", @"strong",
                                            @"weak", @"retain", @"atomic", @"class")
    
    NSMutableArray *attributes = [NSMutableArray array];
    
    ScanAssert([self scanString:@"@property"]);
    if ([self scanString:@"("]) {
        NSString *attr = nil;
        do {
            // Regular attributes
            if ([self scanAny:propAttrs ensureKeyword:YES into:&attr]) {
            } else {
                // getter= / setter= attributes
                ScanAssertPop([self scanAny:propSelectors ensureKeyword:YES into:&attr] && [self scanString:@"="]);
                NSString *selector = nil;
                ScanAssertPop([self scanSelector:&selector]);
                attr = [attr stringByAppendingFormat:@"=%@", selector];
            }
            [attributes addObject:attr]; attr = nil;
        } while ([self scanString:@","]);
        
        ScanAssertPop([self scanString:@")"]);
    }
    
    DCVariable *variable = nil;
    ScanAssertPop([self scanVariable:&variable]);
    
    *output = [DCProperty withAttributes:attributes variable:variable];
    return YES;
}

- (BOOL)scanMethod:(DCMethod **)output {
    ScanPush();
    ScanBuilderInit();
    
    NSMutableArray *types = [NSMutableArray array];
    NSMutableArray *argNames = [NSMutableArray array];
    
    // ('-'|'+') '(' [protocol-qualifier]<type>')'
    BOOL isInstanceMethod = [self scanString:@"-"];
    ScanAssertPop(isInstanceMethod || [self scanString:@"+"]);
    
    ScanAssertPop([self scanString:@"("]);
    ScanAppend_(self scanProtocolQualifier);
    ScanAssertPop(ScanAppend(self scanType) && [self scanString:@")"]);
    [types addObject:__scanned.copy];
    
    // Scan builder will hold the selector
    [__scanned setString:@""];
    
    // <identifier>(":("[protocol-qualifier]<type>')'[identifier])*
    BOOL complete = YES;
    ScanAssertPop(ScanAppend(self scanIdentifier));
    while (ScanAppend(self scanString:@":" intoString)) {
        // Scan parameter (protocol qualifier and type)
        NSString *protocolQualifier = nil, *type = nil, *arg = nil;
        ScanAssertPop([self scanString:@"("]);
        [self scanProtocolQualifier:&protocolQualifier];
        ScanAssertPop([self scanType:&type] && [self scanString:@")"]);
        
        // Add to types
        if (protocolQualifier) {
            type = [NSString stringWithFormat:@"%@ %@", protocolQualifier, type];
        }
        [types addObject:type];
        
        // Scan for parameter name and optional selector part
        if ([self scanIdentifier:&arg]) {
            [argNames addObject:arg];
            // Will be NO if something scans, YES if none found.
            // If none found, we might come across another parameter
            // and this might execute again. `complete` is only used
            // when the loop exits because no ':' was found.
            // So we only encounter an error when a second identifier
            // was scanned but no required ':' was found.
            complete = !ScanAppend(self scanIdentifier); // Optional parameter label
        } else {
            complete = YES;
            break;
        }
    }
    
    ScanAssertPop(complete);
    
    [self scanPastClangAttribute];
    ScanAssertPop([self scanString:@";"]);
    
    if (output) {
        *output = [DCMethod types:types selector:__scanned argumentNames:argNames instance:isInstanceMethod];
    }
    return YES;
}

- (BOOL)scanClassOrProtocolForwardDeclaration:(NSString **)output {
    ScanPush();
    ScanBuilderInit();
    
    ScanAssert(ScanAppend_(self scanString:@"@class" intoString) || ScanAppend_(self scanString:@"@protocol" intoString));
    ScanAssertPop(ScanAppend(self scanIdentifier));
    while (ScanAppend(self scanString:@"," intoString)) {
        ScanAssertPop(ScanAppend(self scanIdentifier));
    }
    
    ScanAssertPop(ScanAppend(self scanString:@";" intoString));
    ScanBuilderWrite(output);
    return YES;
}

- (BOOL)scanObjectType:(NSString **)output {
    ScanPush();
    ScanBuilderInit();
    
    ScanAssertPop(ScanAppend(self scanString:@"id" intoString) || ScanAppend(self scanIdentifier))
    
    // Conformed protocols
    // '<'identifier[, identifier]*'>'
    if (ScanAppend(self scanString:@"<" intoString)) {
        do {
            ScanAssertPop(ScanAppend(self scanIdentifier));
        } while (ScanAppendFormat(self scanString:@"," intoString, @"%@ "));
        
        // Delete trailing ", "
        [__scanned deleteCharactersInRange:NSMakeRange(__scanned.length-2, 2)];
        ScanAssertPop(ScanAppend(self scanString:@">" intoString));
    }
    
    ScanAppend(self scanPointers);
    
    ScanBuilderWrite(output);
    return YES;
}

- (BOOL)scanInterfaceBody:(InterfaceBodyBlock)callback isProtocol:(BOOL)isProtocol {
    ScanPush();
    DCProperty *tmpProp = nil;
    DCMethod *tmpMethod = nil;
    NSMutableArray<DCProperty*> *properties = [NSMutableArray array];
    NSMutableArray<DCMethod*> *methods      = [NSMutableArray array];
    
    BOOL didFind = YES;
    while (didFind) {
        didFind = NO;
        if ([self scanProperty:&tmpProp]) {
            [properties addObject:tmpProp];
            
            tmpProp = nil;
            didFind = YES;
        }
        else if ([self scanMethod:&tmpMethod]) {
            [methods addObject:tmpMethod];
            
            tmpMethod = nil;
            didFind = YES;
        } else {
            // Skip past comments and things like @optional if protocol
            static NSArray *protocolThings = StaticArray(protocolThings, @"@optional", @"@required");
            didFind = isProtocol ? [self scanAny:protocolThings ensureKeyword:YES into:nil] : NO || [self scanPastIgnoredThing];
        }
    }
    
    ScanAssertPop([self scanString:@"@end"]);
    
    callback(properties, methods);
    return YES;
}

- (BOOL)scanProtocolConformanceList:(NSArray<NSString*> **)output {
    ScanAssert([self scanString:@"<"]);
    
    ScanPush();
    NSMutableArray *protocols = [NSMutableArray array];
    NSString *tmp = nil;
    
    do {
        ScanAssertPop([self scanIdentifier:&tmp]);
        [protocols addObject:tmp]; tmp = nil;
    } while ([self scanString:@","]);
    
    ScanAssertPop([self scanString:@">"]);
    
    *output = protocols;
    return YES;
}

- (BOOL)scanInstanceVariableList:(NSArray<DCVariable*> **)output {
    ScanAssert([self scanString:@"{"]);
    
    ScanPush();
    static NSArray *ivarQualifiers = StaticArray(ivarQualifiers, @"@protected", @"@private", @"@public");
    NSMutableArray *ivars = [NSMutableArray array];
    DCVariable *tmp = nil;
    
    while ([self scanAny:ivarQualifiers ensureKeyword:YES into:nil] || [self scanVariable:&tmp]) {
        if (tmp) {
            [ivars addObject:tmp];
            tmp = nil;
        }
    }
    
    ScanAssertPop([self scanString:@"}"]);
    
    *output = ivars;
    return YES;
}

- (BOOL)scanSelector:(NSString **)output {
    ScanBuilderInit();
    
    ScanAssert(ScanAppend(self scanIdentifier));
    while (ScanAppend(self scanString:@":" intoString)) {
        ScanAppend(self scanIdentifier);
    }
    
    ScanBuilderWrite(output);
    return YES;
}

- (BOOL)scanAnyTypedef:(NSString **)output {
    ScanPush();
    ScanBuilderInit();
    
    ScanAssert(ScanAppend(self scanString:@"typedef" intoString));
    ScanAssertPop(ScanAppend(self scanUpToString:@";" intoString) &&
                  ScanAppend(self scanString:@";" intoString));
    
    ScanBuilderWrite(output);
    return YES;
}

/// Starts scanning at "typedef" and scans to ";"
- (BOOL)scanBlockTypedef:(NSString **)output {
    ScanPush();
    ScanBuilderInit();
    
    // block ::= typedef <return-type>"(^"<identifier>")("[parameters]");"
    ScanAssert(ScanAppend_(self scanWord:@"typedef" into));
    ScanAssertPop(ScanAppend(self scanType) &&
                  ScanAppend(self scanString:@"(" intoString) &&
                  ScanAppend(self scanString:@"^" intoString) &&
                  ScanAppend(self scanIdentifier) &&
                  ScanAppend(self scanString:@")" intoString) &&
                  ScanAppend(self scanFunctionParameterList));
    
    [self scanPastClangAttribute];
    ScanAssertPop(ScanAppend(self scanString:@";" intoString));
    
    ScanBuilderWrite(output);
    return YES;
}

/// returnType (^nullability)(parameterTypes) after the :( thing
- (BOOL)scanBlockMethodParameter:(NSString **)output {
    ScanPush();
    ScanBuilderInit();
    
    static NSArray *nullability = StaticArray(nullability, @"nullable", @"nonnull");
    // <returnType> "(^"[nullability]")("[parameterTypes]")"
    
    ScanAssertPop(ScanAppend(self scanType) &&
                  ScanAppend(self scanString:@"(" intoString) &&
                  ScanAppend(self scanString:@"^" intoString) &&
                  ScanAppend(self scanAny:nullability ensureKeyword:YES into) &&
                  ScanAppend(self scanString:@")" intoString) &&
                  ScanAppend(self scanFunctionParameterList));
    
    ScanBuilderWrite(output);
    return YES;
}

/// Scans returnType (^blockName)(parameterTypes) after the property attributes
- (BOOL)scanBlockPropertyVariable:(NSString **)type name:(NSString **)name {
    ScanPush();
    ScanBuilderInit();
    
    // Will probably work for 99% of cases
    ScanAssert([self scanType:type]);
    
    ScanAssertPop(ScanAppend(self scanString:@"(" intoString) &&
                  ScanAppend(self scanString:@"^" intoString) &&
                  ScanAppend(self scanIdentifier) &&
                  ScanAppend(self scanString:@")" intoString) &&
                  ScanAppend(self scanFunctionParameterList));
    
    ScanBuilderWrite(name);
    return YES;
}

#pragma mark C types

- (BOOL)scanPastIgnoredThing {
    ScanPush();
    
    // Comments like this
    if ([self scanString:@"//"]) {
        [self scanPastSpecialMultilineCommentOrMacro];
    }
    /* comemnts like this */ /** or this */
    else if ([self scanString:@"/*"]) {
        ScanAssertPop([self scanToString:@"*/"]);
        ScanAssertPop([self scanString:@"*/"]);
    }
    // #if and #elif
    else if (([self scanString:@"#if"] ||
              [self scanString:@"#include"] || [self scanString:@"#import"]) && [self scanToString:@"\n"]) {
    }
    // Skip all #elif's, we're only going to parse the
    // first branch of all preprocessor conditionals for simplicity.
    else if ([self scanString:@"#elif"]) {
        ScanAssertPop([self scanToString:@"#endif"] && [self scanString:@"#endif"]);
    }
    // #defines, might end with \ which could make it carry onto the next line
    else if ([self scanString:@"#define"]) {
        [self scanPastSpecialMultilineCommentOrMacro];
    }
    else if ([self scanString:@"#endif"]) {
        
    } else if ([self scanString:@"@import"]) {
        ScanAssertPop([self scanIdentifier:nil] && [self scanString:@";"]);
    } else {
        NSString *identifier = nil;
        [self scanIdentifier:&identifier];
        // Only way I know how to check for valid macros rn
        ScanAssertPop([identifier hasPrefix:@"NS_"]);
    }
    
    return YES;
}

- (BOOL)scanPastComment {
    ScanPush();
    
    // Comments like this
    if ([self scanString:@"//"]) {
        [self scanPastSpecialMultilineCommentOrMacro];
        return YES;
    }
    /* comemnts like this */ /** or this */
    else if ([self scanString:@"/*"]) {
        ScanAssertPop([self scanToString:@"*/"]);
        ScanAssertPop([self scanString:@"*/"]);
        return YES;
    }
    
    return NO;
}

- (BOOL)scanVariable:(DCVariable **)output {
    ScanPush();
    ScanBuilderInit();
    
    // The memory and type qualifiers are optional,
    // while type and name are not.
    NSString *identifier = nil;
    ScanAppend_(self scanTypeMemoryQualifier);
    ScanAppend_(self scanTypeQualifier);
    ScanAssertPop(ScanAppend(self scanType) && [self scanIdentifier:&identifier]);
    
    // Static arrays
    if (ScanAppend(self scanString:@"[" intoString)) {
        ScanAssertPop(ScanAppend(self scanNumberLiteral) &&
                      ScanAppend(self scanString:@"]" intoString));
    }
    
    // Skip past clang attributes and macros to the semicolon
    [self scanPastClangAttribute];
    ScanAssertPop([self scanString:@";"]);
    
    if (output) {
        *output = [DCVariable type:__scanned name:identifier];
    }
    return YES;
}

- (BOOL)scanFunctionParameter:(NSString **)output {
    ScanPush();
    ScanBuilderInit();
    
    ScanAppend_(self scanTypeMemoryQualifier);
    ScanAssertPop(ScanAppend_(self scanType));
    // Function parameters are optional
    ScanAppend(self scanIdentifier);
    
    ScanBuilderWrite(output);
    return YES;
}

- (BOOL)scanFunctionParameterList:(NSString **)output {
    ScanPush();
    ScanBuilderInit();
    
    ScanAssert(ScanAppend(self scanString:@"(" intoString));
    
    // Optional parameters
    do {
        ScanAppend(self scanFunctionParameter);
    } while (ScanAppend_(self scanString:@"," intoString));
    
    // Closing parentheses
    ScanAssertPop(ScanAppend(self scanString:@")" intoString));
    
    ScanBuilderWrite(output);
    return YES;
}

- (BOOL)scanCFunction:(NSString **)output {
    ScanPush();
    ScanBuilderInit();
    
    static NSArray *qualifiers = StaticArray(qualifiers, @"extern", @"inline");
    ScanAppend_(self scanWord:@"static" into);
    ScanAppend_(self scanAny:qualifiers ensureKeyword:YES into);
    ScanAppend_(self scanAny:qualifiers ensureKeyword:YES into);
    
    ScanAppend_(self scanTypeMemoryQualifier);
    
    // Function type cannot start with typedef,
    // workaround for preceedence over other stuff
    NSString *type = nil;
    if ([self scanType:&type] && [type isEqualToString:@"typedef"]) {
        ScanPop();
        return NO;
    } else {
        ScanAssertPop(type);
        [__scanned appendString:type];
    }
    
    // Signature and parameters
    ScanAssertPop(ScanAppend(self scanIdentifier) &&
                  ScanAppend(self scanFunctionParameterList));
    
    // Some can be inline, some can be prototypes
    if (ScanAppendFormat(self scanString:@"{" intoString, @"%@\n")) {
        ScanAssertPop([self scanToString:@"}"]);
    } else {
        [self scanPastClangAttribute];
        ScanAppend(self scanString:@";" intoString);
    }
    
    ScanBuilderWrite(output);
    return YES;
}

- (BOOL)scanGlobalVariale:(NSString **)output {
    ScanPush();
    ScanBuilderInit();
    
    ScanAppend_(self scanString:@"extern" intoString);
    ScanAssertPop(ScanAppend_(self scanType));
    ScanAssertPop(ScanAppend(self scanIdentifier));
    [self scanPastClangAttribute];
    ScanAssertPop(ScanAppend(self scanString:@";" intoString));
    
    ScanBuilderWrite(output);
    return YES;
}

- (BOOL)scanTypedefStructUnionOrEnum:(NSString **)output {
    ScanPush();
    ScanBuilderInit();
    
    // Struct and union typedefs are assumed to not have a trailing attribute
    ScanAssert(ScanAppend_(self scanString:@"typedef" intoString));
    if (ScanAppend_(self scanStructOrUnion)) {
        ScanAssertPop(ScanAppend(self scanIdentifier));
    } else {
        ScanAssertPop(ScanAppend_(self scanEnum));
        [self scanPastClangAttribute];
    }
    
    ScanAssertPop(ScanAppend(self scanString:@";" intoString));
    
    ScanBuilderWrite(output);
    return YES;
}

- (BOOL)scanStructOrUnion:(NSString **)output {
    ScanPush();
    ScanBuilderInit();
    
    BOOL isStruct = ScanAppend_(self scanString:@"struct" intoString);
    ScanAssertPop(isStruct || ScanAppend_(self scanString:@"union" intoString));
    ScanAppend_(self scanIdentifier);
    
    ScanAssertPop(ScanAppend_(self scanString:@"{" intoString));
    do {
        DCVariable *var = nil;
        if ([self scanVariable:&var]) {
            [__scanned appendFormat:@"\n\t%@", var.string];
        } else {
            ScanAssertPop(!isStruct || ScanAppendFormat(self scanBitfield, @"\n\t%@"));
        }
    } while (!ScanAppendFormat(self scanString:@"}" intoString, @"\n%@"));
    
    ScanBuilderWrite(output);
    return YES;
}

- (BOOL)scanEnum:(NSString **)output {
    ScanPush();
    ScanBuilderInit();
    // enum ::= [typedef] (enum [identifier]|NS_ENUM'('identifier, identifier')') { types } [attr];
    
    if (ScanAppend_(self scanString:@"enum" intoString)) {
        ScanAppend_(self scanIdentifier);
    }
    else if (ScanAppend(self scanString:@"NS_ENUM" intoString)) {
        // '('type, name')'
        ScanAssertPop(ScanAppend(self scanString:@"(" intoString) && ScanAppend(self scanIdentifier) &&
                      ScanAppend_(self scanString:@"," intoString) && ScanAppend(self scanIdentifier) &&
                      ScanAppend_(self scanString:@")" intoString));
    }
    
    ScanAssertPop(ScanAppend_(self scanString:@"{" intoString));
    
    // val ::= identifier [attr][= expr][, val]
    do {
        ScanAssertPop(ScanAppend_(self scanIdentifier));
        [self scanPastClangAttribute];
        if (ScanAppend_(self scanString:@"=" intoString)) {
            ScanAssertPop(ScanAppend(self scanExpression));
        }
    } while (ScanAppend_(self scanString:@"," intoString));
    ScanAssertPop(ScanAppend(self scanString:@"}" intoString));
    
    ScanBuilderWrite(output);
    return YES;
}

- (BOOL)scanBitfield:(NSString **)output {
    ScanPush();
    ScanBuilderInit();
    
    // The memory and type qualifiers are optional,
    // while type and name are not.
    ScanAppend_(self scanTypeMemoryQualifier);
    ScanAppend_(self scanTypeQualifier);
    ScanAssertPop(ScanAppend_(self scanType) && ScanAppend_(self scanString:@":" intoString) && ScanAppend(self scanIdentifier));
    
    // Skip past clang attributes and macros to the semicolon
    [self scanCharacters:self.variableAttributesCharacterSet];
    ScanAssertPop(ScanAppend(self scanString:@";" intoString));
    
    ScanBuilderWrite(output);
    return YES;
}

#pragma mark Basics

- (BOOL)scanIdentifier:(NSString **)output {
    ScanPush();
    
    // Scan past whitespace, fail if scanned other than whitespace (ie digit)
    ScanAssertPop(![self scanToCharacters:self.alphaCharacterSet]);
    return [self scanCharactersFromSet:self.variableNameCharacterSet intoString:output];
}

- (BOOL)scanTypeMemoryQualifier:(NSString **)output {
    static NSArray *qualifiers = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        qualifiers = @[@"const", @"volatile", @"static"];
    });
    
    return [self scanAny:qualifiers ensureKeyword:YES into:output];
}

- (BOOL)scanTypeQualifier:(NSString **)output {
    static NSArray *qualifiers = StaticArray(qualifiers, @"signed", @"unsigned", @"long");
    return [self scanAny:qualifiers ensureKeyword:YES into:output];
}

- (BOOL)scanProtocolQualifier:(NSString **)output {
    static NSArray *qualifiers = StaticArray(qualifiers, @"in", @"out", @"inout", @"bycopy", @"byref", @"oneway");
    return [self scanAny:qualifiers ensureKeyword:YES into:output];
}

- (BOOL)scanType:(NSString **)output {
    static NSArray *basicTypes = StaticArray(basicTypes, @"void", @"double", @"float", @"long", @"int", @"short", @"char",
                                             @"NSInteger", @"NSUInteger", @"CGFloat");
    static NSArray *complexTypes = StaticArray(complexTypes, @"struct", @"union");
    
    ScanPush();
    ScanBuilderInit();
    
    // Scan for optional static / const / volatile, then for signed / unsigned
    ScanAppend_(self scanTypeMemoryQualifier);
    ScanAppend_(self scanTypeMemoryQualifier);
    ScanAppend_(self scanTypeMemoryQualifier);
    ScanAppend_(self scanTypeQualifier);
    
    // Then primitive types, then pointers and more consts.
    // Might also scan a (maybe anonymous) struct or union.
    if (ScanAppend_(self scanAny:basicTypes ensureKeyword:YES into) || // Basic types
        (ScanAppend_(self scanAny:complexTypes ensureKeyword:YES into) && ScanAppend_(self scanIdentifier)) || // "struct _NSRange"
        ScanAppend_(self scanStructOrUnion)) { // Anonymous struct
        ScanAppend(self scanPointers);
        
        if ([__scanned hasSuffix:@" "]) {
            [__scanned deleteLastCharacter];
        }
        ScanBuilderWrite(output);
        return YES;
    }
    else {
        // Fallback to object types and enums
        BOOL ret = [self scanObjectType:output] || [self scanEnum:output];
        if (!ret) {
            ScanPop();
        }
        
        return ret;
    }
}

- (BOOL)scanPointers:(NSString **)output {
    ScanBuilderInit();
    
    // We scan mutliple times for cases like "** * const * *"
    BOOL hasMemoryQualifier = NO;
    while (ScanAppend(self scanString:@"*" intoString) || (!hasMemoryQualifier && ScanAppend_(self scanTypeMemoryQualifier))) {}
    
    if (__scanned.length) {
        ScanBuilderWrite(output);
        return YES;
    }
    
    return NO;
}

- (BOOL)scanPastSpecialMultilineCommentOrMacro {
    // Carefully scan to the next '\' on the same line, and if
    // it is not followed by '\n', keep checking for that. Then
    // finally check for just a newline.
    while ([self scanToStringOnSameLine:@"\\"]) {
        if ([self scanString:@"\\"] && [self scanString:@"\n"]) {
            break;
        }
    }
    [self scanString:@"\n"];
    
    return YES;
}

- (BOOL)scanPastClangAttribute {
    ScanPush();
    [self scanCharacters:self.variableAttributesCharacterSet];
    if ([self scanString:@"\""]) {
        ScanAssertPop([self scanToStringOnSameLine:@"\""] && [self scanString:@")"]);
    }
    
    return YES;
}

@end
