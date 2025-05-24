//
//  FLEXRuntimeUtility.m
//  Flipboard
//
//  由 Ryan Olson 创建于 6/8/14.
//  版权所有 (c) 2020 FLEX Team. 保留所有权利。
//

#import <UIKit/UIKit.h>
#import "FLEXRuntimeUtility.h"
#import "FLEXObjcInternal.h"
#import "FLEXObjectRef.h"
#import "NSObject+FLEX_Reflection.h"
#import "FLEXTypeEncodingParser.h"
#import "FLEXMethod.h"

NSString * const FLEXRuntimeUtilityErrorDomain = @"FLEXRuntimeUtilityErrorDomain";

@implementation FLEXRuntimeUtility

#pragma mark - 通用辅助方法 (公共)

+ (BOOL)pointerIsValidObjcObject:(const void *)pointer {
    return FLEXPointerIsValidObjcObject(pointer);
}

+ (id)potentiallyUnwrapBoxedPointer:(id)returnedObjectOrNil type:(const FLEXTypeEncoding *)returnType {
    if (!returnedObjectOrNil) {
        return nil;
    }

    NSInteger i = 0;
    if (returnType[i] == FLEXTypeEncodingConst) {
        i++;
    }

    BOOL returnsObjectOrClass = returnType[i] == FLEXTypeEncodingObjcObject ||
                                returnType[i] == FLEXTypeEncodingObjcClass;
    BOOL returnsVoidPointer   = returnType[i] == FLEXTypeEncodingPointer &&
                                returnType[i+1] == FLEXTypeEncodingVoid;
    BOOL returnsCString       = returnType[i] == FLEXTypeEncodingCString;

    // 如果我们得到一个NSValue且返回类型不是对象，
    // 我们检查指针是否是有效对象。如果不是，
    // 我们只显示NSValue。
    if (!returnsObjectOrClass) {
        // 跳过NSNumber实例
        if ([returnedObjectOrNil isKindOfClass:[NSNumber class]]) {
            return returnedObjectOrNil;
        }
        
        // 只能是NSValue，因为返回类型不是对象，
        // 如果这不成立，我们就退出
        if (![returnedObjectOrNil isKindOfClass:[NSValue class]]) {
            return returnedObjectOrNil;
        }

        NSValue *value = (NSValue *)returnedObjectOrNil;

        if (returnsCString) {
            // 将char*包装在NSString中
            const char *string = (const char *)value.pointerValue;
            returnedObjectOrNil = string ? [NSString stringWithCString:string encoding:NSUTF8StringEncoding] : NULL;
        } else if (returnsVoidPointer) {
            // 将伪装为void*的有效对象转换为id
            if ([FLEXRuntimeUtility pointerIsValidObjcObject:value.pointerValue]) {
                returnedObjectOrNil = (__bridge id)value.pointerValue;
            }
        }
    }

    return returnedObjectOrNil;
}

+ (NSUInteger)fieldNameOffsetForTypeEncoding:(const FLEXTypeEncoding *)typeEncoding {
    NSUInteger beginIndex = 0;
    while (typeEncoding[beginIndex] == FLEXTypeEncodingQuote) {
        NSUInteger endIndex = beginIndex + 1;
        while (typeEncoding[endIndex] != FLEXTypeEncodingQuote) {
            ++endIndex;
        }
        beginIndex = endIndex + 1;
    }
    return beginIndex;
}

+ (NSArray<Class> *)classHierarchyOfObject:(id)objectOrClass {
    NSMutableArray<Class> *superClasses = [NSMutableArray new];
    id cls = [objectOrClass class];
    do {
        [superClasses addObject:cls];
    } while ((cls = [cls superclass]));

    return superClasses;
}

+ (NSArray<FLEXObjectRef *> *)subclassesOfClassWithName:(NSString *)className {
    NSArray<Class> *classes = FLEXGetAllSubclasses(NSClassFromString(className), NO);
    NSArray<FLEXObjectRef *> *references = [FLEXObjectRef referencingClasses:classes];
    return references;
}

+ (NSString *)safeClassNameForObject:(id)object {
    // 不要假设我们有一个NSObject子类
    if ([self safeObject:object respondsToSelector:@selector(class)]) {
        return NSStringFromClass([object class]);
    }

    return NSStringFromClass(object_getClass(object));
}

/// 可能为nil
+ (NSString *)safeDescriptionForObject:(id)object {
    // 不要假设我们有一个NSObject子类；并非所有对象都响应-description
    if ([self safeObject:object respondsToSelector:@selector(description)]) {
        @try {
            return [object description];
        } @catch (NSException *exception) {
            return nil;
        }
    }

    return nil;
}

/// 永不为nil
+ (NSString *)safeDebugDescriptionForObject:(id)object {
    NSString *description = nil;

    if ([self safeObject:object respondsToSelector:@selector(debugDescription)]) {
        @try {
            description = [object debugDescription];
        } @catch (NSException *exception) { }
    } else {
        description = [self safeDescriptionForObject:object];
    }

    if (!description.length) {
        NSString *cls = NSStringFromClass(object_getClass(object));
        if (object_isClass(object)) {
            description = [cls stringByAppendingString:@" 类 (无描述)"];
        } else {
            description = [cls stringByAppendingString:@" 实例 (无描述)"];
        }
    }

    return description;
}

+ (NSString *)summaryForObject:(id)value {
    NSString *description = nil;

    // 为了更好的可读性，特殊处理BOOL。
    if ([self safeObject:value isKindOfClass:[NSValue class]]) {
        const char *type = [value objCType];
        if (strcmp(type, @encode(BOOL)) == 0) {
            BOOL boolValue = NO;
            [value getValue:&boolValue];
            return boolValue ? @"YES" : @"NO";
        } else if (strcmp(type, @encode(SEL)) == 0) {
            SEL selector = NULL;
            [value getValue:&selector];
            return NSStringFromSelector(selector);
        }
    }

    @try {
        // 单行显示 - 用空格替换换行符和制表符。
        description = [[self safeDescriptionForObject:value] stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        description = [description stringByReplacingOccurrencesOfString:@"\t" withString:@" "];
        description = [description stringByReplacingOccurrencesOfString:@"    " withString:@" "];
    } @catch (NSException *e) {
        description = [@"抛出: " stringByAppendingString:e.reason ?: @"(无异常原因)"];
    }

    if (!description) {
        description = @"nil";
    }

    return description;
}

+ (BOOL)safeObject:(id)object isKindOfClass:(Class)cls {
    static BOOL (*isKindOfClass)(id, SEL, Class) = nil;
    static BOOL (*isKindOfClass_meta)(id, SEL, Class) = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        isKindOfClass = (BOOL(*)(id, SEL, Class))[NSObject instanceMethodForSelector:@selector(isKindOfClass:)];
        isKindOfClass_meta = (BOOL(*)(id, SEL, Class))[NSObject methodForSelector:@selector(isKindOfClass:)];
    });
    
    BOOL isClass = object_isClass(object);
    return (isClass ? isKindOfClass_meta : isKindOfClass)(object, @selector(isKindOfClass:), cls);
}

+ (BOOL)safeObject:(id)object respondsToSelector:(SEL)sel {
    // 如果我们给定一个类，我们想知道类是否响应此选择器。
    // 同样，如果我们给定一个实例，我们想知道实例是否响应。
    BOOL isClass = object_isClass(object);
    Class cls = isClass ? object : object_getClass(object);
    // BOOL isMetaclass = class_isMetaClass(cls);
    
    if (isClass) {
        // 理论上，这也应该适用于元类...
        return class_getClassMethod(cls, sel) != nil;
    } else {
        return class_getInstanceMethod(cls, sel) != nil;
    }
}


#pragma mark - 属性辅助方法 (公共)

+ (BOOL)tryAddPropertyWithName:(const char *)name
                    attributes:(NSDictionary<NSString *, NSString *> *)attributePairs
                       toClass:(__unsafe_unretained Class)theClass {
    objc_property_t property = class_getProperty(theClass, name);
    if (!property) {
        unsigned int totalAttributesCount = (unsigned int)attributePairs.count;
        objc_property_attribute_t *attributes = malloc(sizeof(objc_property_attribute_t) * totalAttributesCount);
        if (attributes) {
            unsigned int attributeIndex = 0;
            for (NSString *attributeName in attributePairs.allKeys) {
                objc_property_attribute_t attribute;
                attribute.name = attributeName.UTF8String;
                attribute.value = attributePairs[attributeName].UTF8String;
                attributes[attributeIndex++] = attribute;
            }

            BOOL success = class_addProperty(theClass, name, attributes, totalAttributesCount);
            free(attributes);
            return success;
        } else {
            return NO;
        }
    }
    
    return YES;
}

+ (NSArray<NSString *> *)allPropertyAttributeKeys {
    static NSArray<NSString *> *allPropertyAttributeKeys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        allPropertyAttributeKeys = @[
            kFLEXPropertyAttributeKeyTypeEncoding,
            kFLEXPropertyAttributeKeyBackingIvarName,
            kFLEXPropertyAttributeKeyReadOnly,
            kFLEXPropertyAttributeKeyCopy,
            kFLEXPropertyAttributeKeyRetain,
            kFLEXPropertyAttributeKeyNonAtomic,
            kFLEXPropertyAttributeKeyCustomGetter,
            kFLEXPropertyAttributeKeyCustomSetter,
            kFLEXPropertyAttributeKeyDynamic,
            kFLEXPropertyAttributeKeyWeak,
            kFLEXPropertyAttributeKeyGarbageCollectable,
            kFLEXPropertyAttributeKeyOldStyleTypeEncoding,
        ];
    });

    return allPropertyAttributeKeys;
}


#pragma mark - 方法辅助方法 (公共)

+ (NSArray<NSString *> *)prettyArgumentComponentsForMethod:(Method)method {
    NSMutableArray<NSString *> *components = [NSMutableArray new];

    NSString *selectorName = NSStringFromSelector(method_getName(method));
    NSMutableArray<NSString *> *selectorComponents = [selectorName componentsSeparatedByString:@":"].mutableCopy;

    // 这是一个解决方法，因为method_getNumberOfArguments()对于某些方法返回错误的数量
    if (selectorComponents.count == 1) {
        return @[];
    }

    if ([selectorComponents.lastObject isEqualToString:@""]) {
        [selectorComponents removeLastObject];
    }

    for (unsigned int argIndex = 0; argIndex < selectorComponents.count; argIndex++) {
        char *argType = method_copyArgumentType(method, argIndex + kFLEXNumberOfImplicitArgs);
        NSString *readableArgType = (argType != NULL) ? [self readableTypeForEncoding:@(argType)] : nil;
        free(argType);
        NSString *prettyComponent = [NSString
            stringWithFormat:@"%@:(%@) ",
            selectorComponents[argIndex],
            readableArgType
        ];
        [components addObject:prettyComponent];
    }

    return components;
}


#pragma mark - 方法调用/字段编辑 (公共)

+ (id)performSelector:(SEL)selector onObject:(id)object {
    return [self performSelector:selector onObject:object withArguments:@[] error:nil];
}

+ (id)performSelector:(SEL)selector
             onObject:(id)object
        withArguments:(NSArray *)arguments
                error:(NSError * __autoreleasing *)error {
    return [self performSelector:selector
        onObject:object
        withArguments:arguments
        allowForwarding:NO
        error:error
    ];
}

+ (id)performSelector:(SEL)selector
             onObject:(id)object
        withArguments:(NSArray *)arguments
      allowForwarding:(BOOL)mightForwardMsgSend
                error:(NSError * __autoreleasing *)error {
    static dispatch_once_t onceToken;
    static SEL stdStringExclusion = nil;
    dispatch_once(&onceToken, ^{
        stdStringExclusion = NSSelectorFromString(@"stdString");
    });

    // 如果对象不会响应此选择器，则退出
    if (mightForwardMsgSend || ![self safeObject:object respondsToSelector:selector]) {
        if (error) {
            NSString *msg = [NSString
                stringWithFormat:@"此对象不响应选择器 %@",
                NSStringFromSelector(selector)
            ];
            NSDictionary<NSString *, id> *userInfo = @{ NSLocalizedDescriptionKey : msg };
            *error = [NSError
                errorWithDomain:FLEXRuntimeUtilityErrorDomain
                code:FLEXRuntimeUtilityErrorCodeDoesNotRecognizeSelector
                userInfo:userInfo
            ];
        }

        return nil;
    }

    // 在这里使用object_getClass而不是-class很重要，因为
    // object_getClass对类对象会返回不同的结果
    Class cls = object_getClass(object);
    NSMethodSignature *methodSignature = [FLEXMethod selector:selector class:cls].signature;
    if (!methodSignature) {
        // 不支持的类型编码
        return nil;
    }
    
    // 可能是不支持的类型编码，如位字段。
    // 将来，我们可以自己计算返回长度。
    // 目前，我们中止。
    //
    // 供将来参考，这里的代码将获取真实的类型编码。
    // NSMethodSignature会将{?=b8b4b1b1b18[8S]}转换为{?}
    //
    // returnType = method_getTypeEncoding(class_getInstanceMethod([object class], selector));
    if (!methodSignature.methodReturnLength &&
        methodSignature.methodReturnType[0] != FLEXTypeEncodingVoid) {
        return nil;
    }

    // 构建调用
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSignature];
    [invocation setSelector:selector];
    [invocation setTarget:object];
    [invocation retainArguments];

    // 总是有self和_cmd
    NSUInteger numberOfArguments = methodSignature.numberOfArguments;
    for (NSUInteger argumentIndex = kFLEXNumberOfImplicitArgs; argumentIndex < numberOfArguments; argumentIndex++) {
        NSUInteger argumentsArrayIndex = argumentIndex - kFLEXNumberOfImplicitArgs;
        id argumentObject = arguments.count > argumentsArrayIndex ? arguments[argumentsArrayIndex] : nil;

        // 参数数组中的NSNull可以作为占位符传递以表示nil。
        // 只有当参数为非nil时，我们才需要设置参数。
        if (argumentObject && ![argumentObject isKindOfClass:[NSNull class]]) {
            const char *typeEncodingCString = [methodSignature getArgumentTypeAtIndex:argumentIndex];
            if (typeEncodingCString[0] == FLEXTypeEncodingObjcObject ||
              typeEncodingCString[0] == FLEXTypeEncodingObjcClass ||
              [self isTollFreeBridgedValue:argumentObject forCFType:typeEncodingCString]) {
                // 对象
                [invocation setArgument:&argumentObject atIndex:argumentIndex];
            } else if (strcmp(typeEncodingCString, @encode(CGColorRef)) == 0 &&
                    [argumentObject isKindOfClass:[UIColor class]]) {
                // 将UIColor桥接到CGColorRef
                CGColorRef colorRef = [argumentObject CGColor];
                [invocation setArgument:&colorRef atIndex:argumentIndex];
            } else if ([argumentObject isKindOfClass:[NSValue class]]) {
                // 在NSValue中装箱的基本类型
                NSValue *argumentValue = (NSValue *)argumentObject;

                // 确保NSValue上的类型编码与方法签名中参数的类型编码匹配
                if (strcmp([argumentValue objCType], typeEncodingCString) != 0) {
                    if (error) {
                        NSString *msg =  [NSString
                            stringWithFormat:@"索引%lu处参数的类型编码不匹配。"
                            "值类型: %s; 方法参数类型: %s.",
                            (unsigned long)argumentsArrayIndex, argumentValue.objCType, typeEncodingCString
                        ];
                        NSDictionary<NSString *, id> *userInfo = @{ NSLocalizedDescriptionKey : msg };
                        *error = [NSError
                            errorWithDomain:FLEXRuntimeUtilityErrorDomain
                            code:FLEXRuntimeUtilityErrorCodeArgumentTypeMismatch
                            userInfo:userInfo
                        ];
                    }
                    return nil;
                }

                @try {
                    NSUInteger bufferSize = 0;
                    FLEXGetSizeAndAlignment(typeEncodingCString, &bufferSize, NULL);

                    if (bufferSize > 0) {
                        void *buffer = alloca(bufferSize);
                        [argumentValue getValue:buffer];
                        [invocation setArgument:buffer atIndex:argumentIndex];
                    }
                } @catch (NSException *exception) { }
            }
        }
    }

    // 尝试调用调用，但防止抛出异常。
    id returnObject = nil;
    @try {
        [invocation invoke];

        // 检索返回值并在必要时装箱。
        const char *returnType = methodSignature.methodReturnType;

        if (returnType[0] == FLEXTypeEncodingObjcObject || returnType[0] == FLEXTypeEncodingObjcClass) {
            // 返回值是一个对象。
            __unsafe_unretained id objectReturnedFromMethod = nil;
            [invocation getReturnValue:&objectReturnedFromMethod];
            returnObject = objectReturnedFromMethod;
        } else if (returnType[0] != FLEXTypeEncodingVoid) {
            NSAssert(methodSignature.methodReturnLength, @"前方有内存损坏");

            if (returnType[0] == FLEXTypeEncodingStructBegin) {
                if (selector == stdStringExclusion && [object isKindOfClass:[NSString class]]) {
                    // stdString是一个C++对象，如果我们尝试访问它，我们会崩溃
                    if (error) {
                        *error = [NSError
                            errorWithDomain:FLEXRuntimeUtilityErrorDomain
                            code:FLEXRuntimeUtilityErrorCodeInvocationFailed
                            userInfo:@{ NSLocalizedDescriptionKey : @"跳过 -[NSString stdString]" }
                        ];
                    }

                    return nil;
                }
            }

            // 将使用任意缓冲区作为返回值并进行装箱。
            void *returnValue = malloc(methodSignature.methodReturnLength);
            [invocation getReturnValue:returnValue];
            returnObject = [self valueForPrimitivePointer:returnValue objCType:returnType];
            free(returnValue);
        }
    } @catch (NSException *exception) {
        // 糟糕...
        if (error) {
            // "… on <class>" / "… on instance of <class>"
            NSString *class = NSStringFromClass([object class]);
            NSString *calledOn = object == [object class] ? class : [@"一个实例: " stringByAppendingString:class];

            NSString *message = [NSString
                stringWithFormat:@"执行选择器'%@'时在%@上抛出异常'%@'。\n原因:\n\n%@",
                NSStringFromSelector(selector), calledOn, exception.name, exception.reason
            ];

            *error = [NSError
                errorWithDomain:FLEXRuntimeUtilityErrorDomain
                code:FLEXRuntimeUtilityErrorCodeInvocationFailed
                userInfo:@{ NSLocalizedDescriptionKey : message }
            ];
        }
    }

    return returnObject;
}

+ (BOOL)isTollFreeBridgedValue:(id)value forCFType:(const char *)typeEncoding {
    // 参见 https://developer.apple.com/library/archive/documentation/General/Conceptual/CocoaEncyclopedia/Toll-FreeBridgin/Toll-FreeBridgin.html
#define CASE(cftype, foundationClass) \
    if (strcmp(typeEncoding, @encode(cftype)) == 0) { \
        return [value isKindOfClass:[foundationClass class]]; \
    }

    CASE(CFArrayRef, NSArray);
    CASE(CFAttributedStringRef, NSAttributedString);
    CASE(CFCalendarRef, NSCalendar);
    CASE(CFCharacterSetRef, NSCharacterSet);
    CASE(CFDataRef, NSData);
    CASE(CFDateRef, NSDate);
    CASE(CFDictionaryRef, NSDictionary);
    CASE(CFErrorRef, NSError);
    CASE(CFLocaleRef, NSLocale);
    CASE(CFMutableArrayRef, NSMutableArray);
    CASE(CFMutableAttributedStringRef, NSMutableAttributedString);
    CASE(CFMutableCharacterSetRef, NSMutableCharacterSet);
    CASE(CFMutableDataRef, NSMutableData);
    CASE(CFMutableDictionaryRef, NSMutableDictionary);
    CASE(CFMutableSetRef, NSMutableSet);
    CASE(CFMutableStringRef, NSMutableString);
    CASE(CFNumberRef, NSNumber);
    CASE(CFReadStreamRef, NSInputStream);
    CASE(CFRunLoopTimerRef, NSTimer);
    CASE(CFSetRef, NSSet);
    CASE(CFStringRef, NSString);
    CASE(CFTimeZoneRef, NSTimeZone);
    CASE(CFURLRef, NSURL);
    CASE(CFWriteStreamRef, NSOutputStream);

#undef CASE

    return NO;
}

+ (NSString *)editableJSONStringForObject:(id)object {
    NSString *editableDescription = nil;

    if (object) {
        // 这是一个使用JSON序列化来编辑对象的黑客手段。
        // NSJSONSerialization不允许写入片段 - 顶级对象必须是数组或字典。
        // 我们总是将对象包装在一个数组中，然后从最终字符串中去掉外部方括号。
        NSArray *wrappedObject = @[object];
        if ([NSJSONSerialization isValidJSONObject:wrappedObject]) {
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:wrappedObject options:0 error:NULL];
            NSString *wrappedDescription = [NSString stringWithUTF8String:jsonData.bytes];
            editableDescription = [wrappedDescription substringWithRange:NSMakeRange(1, wrappedDescription.length - 2)];
        }
    }

    return editableDescription;
}

+ (id)objectValueFromEditableJSONString:(NSString *)string {
    id value = nil;
    // nil表示空字符串/空白
    if ([string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) {
        value = [NSJSONSerialization
            JSONObjectWithData:[string dataUsingEncoding:NSUTF8StringEncoding]
            options:NSJSONReadingAllowFragments
            error:NULL
        ];
    }
    return value;
}

+ (NSValue *)valueForNumberWithObjCType:(const char *)typeEncoding fromInputString:(NSString *)inputString {
    NSNumberFormatter *formatter = [NSNumberFormatter new];
    [formatter setNumberStyle:NSNumberFormatterDecimalStyle];
    NSNumber *number = [formatter numberFromString:inputString];
    
    // 类型编码是否超过一个字符？
    if (strlen(typeEncoding) > 1) {
        NSString *type = @(typeEncoding);
        
        // 是NSDecimalNumber还是NSNumber？
        if ([type isEqualToString:@FLEXEncodeClass(NSDecimalNumber)]) {
            return [NSDecimalNumber decimalNumberWithString:inputString];
        } else if ([type isEqualToString:@FLEXEncodeClass(NSNumber)]) {
            return number;
        }
        
        return nil;
    }
    
    // 类型编码是一个字符，切换类型
    FLEXTypeEncoding type = typeEncoding[0];
    uint8_t value[32];
    void *bufferStart = &value[0];
    
    // 确保我们用正确的类型编码装箱数字
    // 以便稍后通过getValue:正确解箱：
    switch (type) {
        case FLEXTypeEncodingChar:
            *(char *)bufferStart = number.charValue; break;
        case FLEXTypeEncodingInt:
            *(int *)bufferStart = number.intValue; break;
        case FLEXTypeEncodingShort:
            *(short *)bufferStart = number.shortValue; break;
        case FLEXTypeEncodingLong:
            *(long *)bufferStart = number.longValue; break;
        case FLEXTypeEncodingLongLong:
            *(long long *)bufferStart = number.longLongValue; break;
        case FLEXTypeEncodingUnsignedChar:
            *(unsigned char *)bufferStart = number.unsignedCharValue; break;
        case FLEXTypeEncodingUnsignedInt:
            *(unsigned int *)bufferStart = number.unsignedIntValue; break;
        case FLEXTypeEncodingUnsignedShort:
            *(unsigned short *)bufferStart = number.unsignedShortValue; break;
        case FLEXTypeEncodingUnsignedLong:
            *(unsigned long *)bufferStart = number.unsignedLongValue; break;
        case FLEXTypeEncodingUnsignedLongLong:
            *(unsigned long long *)bufferStart = number.unsignedLongLongValue; break;
        case FLEXTypeEncodingFloat:
            *(float *)bufferStart = number.floatValue; break;
        case FLEXTypeEncodingDouble:
            *(double *)bufferStart = number.doubleValue; break;
            
        case FLEXTypeEncodingLongDouble:
            // NSNumber不支持long double
        default:
            return nil;
    }
    
    return [NSValue value:value withObjCType:typeEncoding];
}

+ (void)enumerateTypesInStructEncoding:(const char *)structEncoding
                            usingBlock:(void (^)(NSString *structName,
                                                 const char *fieldTypeEncoding,
                                                 NSString *prettyTypeEncoding,
                                                 NSUInteger fieldIndex,
                                                 NSUInteger fieldOffset))typeBlock {
    if (structEncoding && structEncoding[0] == FLEXTypeEncodingStructBegin) {
        const char *equals = strchr(structEncoding, '=');
        if (equals) {
            const char *nameStart = structEncoding + 1;
            NSString *structName = [@(structEncoding)
                substringWithRange:NSMakeRange(nameStart - structEncoding, equals - nameStart)
            ];

            NSUInteger fieldAlignment = 0, structSize = 0;
            if (FLEXGetSizeAndAlignment(structEncoding, &structSize, &fieldAlignment)) {
                NSUInteger runningFieldIndex = 0;
                NSUInteger runningFieldOffset = 0;
                const char *typeStart = equals + 1;
                
                while (*typeStart != FLEXTypeEncodingStructEnd) {
                    NSUInteger fieldSize = 0;
                    // 如果结构体类型编码由FLEXGetSizeAndAlignment成功处理
                    // 我们*应该*在这里处理字段没问题。
                    const char *nextTypeStart = NSGetSizeAndAlignment(typeStart, &fieldSize, NULL);
                    NSString *typeEncoding = [@(structEncoding)
                        substringWithRange:NSMakeRange(typeStart - structEncoding, nextTypeStart - typeStart)
                    ];
                    
                    // 填充以保持正确的对齐。__attribute((packed))结构体
                    // 会在这里出问题。紧凑结构体的类型编码没有不同，
                    // 所以不清楚我们能为它们做些什么。
                    const NSUInteger currentSizeSum = runningFieldOffset % fieldAlignment;
                    if (currentSizeSum != 0 && currentSizeSum + fieldSize > fieldAlignment) {
                        runningFieldOffset += fieldAlignment - currentSizeSum;
                    }
                    
                    typeBlock(
                        structName,
                        typeEncoding.UTF8String,
                        [self readableTypeForEncoding:typeEncoding],
                        runningFieldIndex,
                        runningFieldOffset
                    );
                    runningFieldOffset += fieldSize;
                    runningFieldIndex++;
                    typeStart = nextTypeStart;
                }
            }
        }
    }
}


#pragma mark - 元数据辅助方法

+ (NSDictionary<NSString *, NSString *> *)attributesForProperty:(objc_property_t)property {
    NSString *attributes = @(property_getAttributes(property) ?: "");
    // 感谢MAObjcRuntime在这里的灵感。
    NSArray<NSString *> *attributePairs = [attributes componentsSeparatedByString:@","];
    NSMutableDictionary<NSString *, NSString *> *attributesDictionary = [NSMutableDictionary new];
    for (NSString *attributePair in attributePairs) {
        attributesDictionary[[attributePair substringToIndex:1]] = [attributePair substringFromIndex:1];
    }
    return attributesDictionary;
}

+ (NSString *)appendName:(NSString *)name toType:(NSString *)type {
    if (!type.length) {
        type = @"(?)";
    }
    
    NSString *combined = nil;
    if ([type characterAtIndex:type.length - 1] == FLEXTypeEncodingCString) {
        combined = [type stringByAppendingString:name];
    } else {
        combined = [type stringByAppendingFormat:@" %@", name];
    }
    return combined;
}

+ (NSString *)readableTypeForEncoding:(NSString *)encodingString {
    if (!encodingString.length) {
        return @"?";
    }

    // 参见 https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtTypeEncodings.html
    // class-dump有一个更好更完整的实现，但它是在GPLv2下分发的 :/
    // 参见 https://github.com/nygard/class-dump/blob/master/Source/CDType.m
    // 警告：此方法使用多个中间返回和宏来减少样板代码。
    // 这里使用宏的灵感来自 https://www.mikeash.com/pyblog/friday-qa-2013-02-08-lets-build-key-value-coding.html
    const char *encodingCString = encodingString.UTF8String;

    // 有些字段有名字，如{Size=\"width\"d\"height\"d}，我们需要提取名字并递归
    const NSUInteger fieldNameOffset = [FLEXRuntimeUtility fieldNameOffsetForTypeEncoding:encodingCString];
    if (fieldNameOffset > 0) {
        // 根据 https://github.com/nygard/class-dump/commit/33fb5ed221810685f57c192e1ce8ab6054949a7c，
        // 有一些连续的带引号的字符串，所以使用`_`来连接名字。
        NSString *const fieldNamesString = [encodingString substringWithRange:NSMakeRange(0, fieldNameOffset)];
        NSArray<NSString *> *const fieldNames = [fieldNamesString
            componentsSeparatedByString:[NSString stringWithFormat:@"%c", FLEXTypeEncodingQuote]
        ];
        NSMutableString *finalFieldNamesString = [NSMutableString new];
        for (NSString *const fieldName in fieldNames) {
            if (fieldName.length > 0) {
                if (finalFieldNamesString.length > 0) {
                    [finalFieldNamesString appendString:@"_"];
                }
                [finalFieldNamesString appendString:fieldName];
            }
        }
        NSString *const recursiveType = [self readableTypeForEncoding:[encodingString substringFromIndex:fieldNameOffset]];
        return [NSString stringWithFormat:@"%@ %@", recursiveType, finalFieldNamesString];
    }

    // 对象
    if (encodingCString[0] == FLEXTypeEncodingObjcObject) {
        NSString *class = [encodingString substringFromIndex:1];
        class = [class stringByReplacingOccurrencesOfString:@"\"" withString:@""];
        if (class.length == 0 || (class.length == 1 && [class characterAtIndex:0] == FLEXTypeEncodingUnknown)) {
            class = @"id";
        } else {
            class = [class stringByAppendingString:@" *"];
        }
        return class;
    }

    // 限定符前缀
    // 先做这个，因为一些直接翻译（如Method）包含前缀。
#define RECURSIVE_TRANSLATE(prefix, formatString) \
    if (encodingCString[0] == prefix) { \
        NSString *recursiveType = [self readableTypeForEncoding:[encodingString substringFromIndex:1]]; \
        return [NSString stringWithFormat:formatString, recursiveType]; \
    }

    // 如果编码上有限定符前缀，翻译它然后
    // 递归调用此方法处理编码字符串的其余部分。
    RECURSIVE_TRANSLATE('^', @"%@ *");
    RECURSIVE_TRANSLATE('r', @"const %@");
    RECURSIVE_TRANSLATE('n', @"in %@");
    RECURSIVE_TRANSLATE('N', @"inout %@");
    RECURSIVE_TRANSLATE('o', @"out %@");
    RECURSIVE_TRANSLATE('O', @"bycopy %@");
    RECURSIVE_TRANSLATE('R', @"byref %@");
    RECURSIVE_TRANSLATE('V', @"oneway %@");
    RECURSIVE_TRANSLATE('b', @"bitfield(%@)");

#undef RECURSIVE_TRANSLATE

  // C类型
#define TRANSLATE(ctype) \
    if (strcmp(encodingCString, @encode(ctype)) == 0) { \
        return (NSString *)CFSTR(#ctype); \
    }

    // 这里顺序很重要，因为一些cocoa类型是从c类型typedefed而来的。
    // 我们无法恢复确切的映射，但我们选择更喜欢cocoa类型。
    // 这不是一个详尽的列表，但它涵盖了最常见的类型
    TRANSLATE(CGRect);
    TRANSLATE(CGPoint);
    TRANSLATE(CGSize);
    TRANSLATE(CGVector);
    TRANSLATE(UIEdgeInsets);
    if (@available(iOS 11.0, *)) {
      TRANSLATE(NSDirectionalEdgeInsets);
    }
    TRANSLATE(UIOffset);
    TRANSLATE(NSRange);
    TRANSLATE(CGAffineTransform);
    TRANSLATE(CATransform3D);
    TRANSLATE(CGColorRef);
    TRANSLATE(CGPathRef);
    TRANSLATE(CGContextRef);
    TRANSLATE(NSInteger);
    TRANSLATE(NSUInteger);
    TRANSLATE(CGFloat);
    TRANSLATE(BOOL);
    TRANSLATE(int);
    TRANSLATE(short);
    TRANSLATE(long);
    TRANSLATE(long long);
    TRANSLATE(unsigned char);
    TRANSLATE(unsigned int);
    TRANSLATE(unsigned short);
    TRANSLATE(unsigned long);
    TRANSLATE(unsigned long long);
    TRANSLATE(float);
    TRANSLATE(double);
    TRANSLATE(long double);
    TRANSLATE(char *);
    TRANSLATE(Class);
    TRANSLATE(objc_property_t);
    TRANSLATE(Ivar);
    TRANSLATE(Method);
    TRANSLATE(Category);
    TRANSLATE(NSZone *);
    TRANSLATE(SEL);
    TRANSLATE(void);

#undef TRANSLATE

    // 对于结构体，我们只使用结构体的名称
    if (encodingCString[0] == FLEXTypeEncodingStructBegin) {
        // 特殊情况：std::string
        if ([encodingString hasPrefix:@"{basic_string<char"]) {
            return @"std::string";
        }

        const char *equals = strchr(encodingCString, '=');
        if (equals) {
            const char *nameStart = encodingCString + 1;
            // 对于匿名结构体
            if (nameStart[0] == FLEXTypeEncodingUnknown) {
                return @"匿名结构体";
            } else {
                NSString *const structName = [encodingString
                    substringWithRange:NSMakeRange(nameStart - encodingCString, equals - nameStart)
                ];
                return structName;
            }
        }
    }

    // 如果我们无法翻译，就返回原始编码字符串
    return encodingString;
}


#pragma mark - 内部辅助方法

+ (NSValue *)valueForPrimitivePointer:(void *)pointer objCType:(const char *)type {
    // 如果有字段名，移除它（例如 \"width\"d -> d）
    const NSUInteger fieldNameOffset = [FLEXRuntimeUtility fieldNameOffsetForTypeEncoding:type];
    if (fieldNameOffset > 0) {
        return [self valueForPrimitivePointer:pointer objCType:type + fieldNameOffset];
    }

    // CASE宏的灵感来自 https://www.mikeash.com/pyblog/friday-qa-2013-02-08-lets-build-key-value-coding.html
#define CASE(ctype, selectorpart) \
    if (strcmp(type, @encode(ctype)) == 0) { \
        return [NSNumber numberWith ## selectorpart: *(ctype *)pointer]; \
    }

    CASE(BOOL, Bool);
    CASE(unsigned char, UnsignedChar);
    CASE(short, Short);
    CASE(unsigned short, UnsignedShort);
    CASE(int, Int);
    CASE(unsigned int, UnsignedInt);
    CASE(long, Long);
    CASE(unsigned long, UnsignedLong);
    CASE(long long, LongLong);
    CASE(unsigned long long, UnsignedLongLong);
    CASE(float, Float);
    CASE(double, Double);
    CASE(long double, Double);

#undef CASE

    NSValue *value = nil;
    if (FLEXGetSizeAndAlignment(type, nil, nil)) {
        @try {
            value = [NSValue valueWithBytes:pointer objCType:type];
        } @catch (NSException *exception) {
            // 某些类型编码不被valueWithBytes:objCType:支持。
            // 如果抛出异常，就静默失败。
        }
    }

    return value;
}

@end
