//
//  DCClass.m
//  dump-cleaner
//
//  Created by Tanner on 3/20/16.
//  Copyright © 2016 Tanner Bennett. All rights reserved.
//

#import "DCClass.h"
#import "DCProperty.h"
#import "DCProtocol.h"
#import "DCMethod.h"


@interface DCClass ()
@property (nonatomic) NSMutableArray<DCVariable*> *ivars;
@property (nonatomic) DCClass *dc_superclass;
@end

@implementation DCClass

#pragma mark Initializers

- (id)initWithString:(NSString *)string {
    _ivars = [NSMutableArray array];
    return [super initWithString:string];
}

#pragma mark Public interface

- (NSString *)outputLocation {
    if (_outputDirectory) {
        if (self.categoryName) {
            NSString *filename = [NSString stringWithFormat:@"%@+%@.h", self.name, self.categoryName];
            return [_outputDirectory stringByAppendingPathComponent:filename];
        }
        
        return [_outputDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.h", self.name]];
    }
    
    return nil;
}

- (void)setOutputDirectory:(NSString *)outputDirectory {
    NSParameterAssert(outputDirectory);
    _outputDirectory = outputDirectory;
    NSString *nameToUse = self.categoryName ?: [self.name stringByAppendingString:@"+AppleInternal"];
    _importStatement = DCImportStatement(outputDirectory, nameToUse);
}

#pragma mark Internal

- (NSString *)categoryKey { return self.categoryName ? [self.name stringByAppendingString:self.categoryName] : nil; }

- (BOOL)isEqual:(id)object {
    if ([object isKindOfClass:[self class]])
        return [self isEqualToDCClass:object];
    
    return [super isEqual:object];
}

- (BOOL)isEqualToDCClass:(DCClass *)class {
    NSString *myKey = self.categoryKey;
    NSString *otherKey = class.categoryKey;
    
    if (myKey && otherKey) {
        return [myKey isEqualToString:otherKey];
    } else if (!myKey && !otherKey) {
        return [self.name isEqualToString:class.name];
    }
    
    return NO;
}

- (NSUInteger)hash { return _categoryName ? self.categoryKey.hash : self.name.hash; }

#pragma mark Processing

- (void)updateWithKnownClasses:(NSArray<DCClass*> *)classes {
    // Find superclass
    for (DCClass *class in classes) {
        if ([class.name isEqualToString:self.superclassName]) {
            self.dc_superclass = class;
            break;
        }
    }
    
    [super updateWithKnownClasses:classes];
}

#pragma mark Searching

- (BOOL)buildString {
    [super buildString];
    [_string appendFormat:@"\n\n@interface %@", _name];
    
    if (_categoryName) {
        // Category
        [_string appendFormat:@" (%@)", _categoryName];
        
        // Conformed protocols
        if (self.conformedProtocols.count) {
            [_string appendString:@" <"];
            for (NSString *prot in self.conformedProtocols) {
                [_string appendFormat:@"%@, ", prot];
            }
            [_string appendString:@">"];
            [_string deleteLastCharacter];
        }
    }
    else {
        // Superclass
        if (_superclassName) {
            [_string appendFormat:@" : %@", _superclassName];
        }
        // Conformed protocols
        if (self.conformedProtocols.count) {
            [_string appendString:@"<"];
            for (NSString *prot in self.conformedProtocols) {
                [_string appendFormat:@"%@, ", prot];
            }
            [_string appendString:@">"];
            [_string deleteLastCharacter];
        }
        // Ivars
        if (self.ivars.count) {
            [_string appendString:@"{\n"];
            for (DCVariable *ivar in self.ivars) {
                [_string appendFormat:@"    %@;\n", ivar.string];
            }
            [_string appendString:@"}"];
        }
    }
    
    // Properties and methods
    [_string appendString:@"\n\n"];
    for (DCProperty *property in self.properties)
        [_string appendFormat:@"%@\n", property.string];
    for (DCMethod *method in self.methods)
        [_string appendFormat:@"%@\n", method.string];
    
    [_string appendString:@"@end\n"];
    
    return YES;
}

- (BOOL)parseOriginalString {
    NSAssert(_orig != nil, @"_orig should be initialized here");
    NSScanner *scanner = [NSScanner scannerWithString:_orig];
    NSString *tmp = nil;
    
    ScanAssert([scanner scanString:@"@interface"]);
    ScanAssert([scanner scanIdentifier:&tmp]);
    _name = tmp; tmp = nil;
    
    BOOL needsSuperclass = NO;
    NSInteger rightAfterClassName = scanner.scanLocation;
    if ([scanner scanString:@"<"]) {
        [scanner scanPastClosingAngleBracket:nil];
        needsSuperclass = YES;
    }
    
    if ([scanner scanString:@"("]) {
        // Category name
        ScanAssert([scanner scanIdentifier:&tmp]);
        _categoryName = tmp; tmp = nil;
        ScanAssert([scanner scanString:@")"])
        
        // Conformed protocols
        NSArray *protocols = nil;
        if ([scanner scanProtocolConformanceList:&protocols]) {
            self.conformedProtocols = protocols;
        }
    } else {
        // Superclass
        if ([scanner scanString:@":"]) {
            ScanAssert([scanner scanIdentifier:&tmp]);
            _superclassName = tmp; tmp = nil;
        } else if (needsSuperclass) {
            // Case for classes like NSObject:
            // @interface NSObject <NSObject>
            scanner.scanLocation = rightAfterClassName;
        }
        
        // Conformed protocols
        NSArray *protocols = nil;
        if ([scanner scanProtocolConformanceList:&protocols]) {
            self.conformedProtocols = protocols;
        }
        // IVars
        NSArray *ivars = nil;
        if ([scanner scanInstanceVariableList:&ivars]) {
            [self.ivars addObjectsFromArray:ivars];
        }
    }
    
    ScanAssert([scanner scanInterfaceBody:^(NSArray<DCProperty *> *properties, NSArray<DCMethod *> *methods) {
        [self.properties addObjectsFromArray:properties];
        [self.methods addObjectsFromArray:methods];
    } isProtocol:NO]);
    
    return YES;
}

- (void)removePropertyBackingIVars {
    NSSet *ivars = [NSSet setWithArray:self.ivars];
    for (DCProperty *property in self.properties)
        if ([ivars containsObject:property.ivar])
            [self.ivars removeObject:property.ivar];
}

- (void)removePropertyMethods {
    [self.methods filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(DCMethod *method, NSDictionary *bindings) {
        for (DCProperty *property in self.properties) {
            if ([method.selectorString isEqualToString:property.getterSelector] ||
                [method.string isEqualToString:property.setterSelector]) {
                return NO;
            }
        }
        return YES;
    }]];
}

- (void)removeNSObjectMethodsAndProperties {
    NSArray *selectors = @[@"class", @"hash", @"self", @"superclass", @"isEqual:"];
    [self.methods filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(DCMethod *method, NSDictionary *bindings) {
        return ![selectors containsObject:method.selectorString];
    }]];
}

- (void)removeSuperclassMethods {
    // TODO, this will be difficult
}

@end
