//
//  FLEXProperty.h
//  FLEX
//
//  派生自 MirrorKit.
//  Created by Tanner on 6/30/15.
//  Copyright (c) 2020 FLEX Team. All rights reserved.
//

#import "FLEXRuntimeConstants.h"
@class FLEXPropertyAttributes, FLEXMethodBase;


#pragma mark FLEXProperty
@interface FLEXProperty : NSObject

/// 如果您不需要了解此属性的唯一性或其来源，可以使用此初始化器代替 \c property:onClass:
+ (instancetype)property:(objc_property_t)property;
/// 此初始化器可用于以高效方式访问其他信息。
/// 这些信息包括此属性是否肯定不唯一以及声明它的二进制映像的名称。
/// @param cls 类，如果这是类属性则为元类。
+ (instancetype)property:(objc_property_t)property onClass:(Class)cls;
/// @param cls 类，如果这是类属性则为元类
+ (instancetype)named:(NSString *)name onClass:(Class)cls;
/// 使用给定的名称和属性构造一个新属性。
+ (instancetype)propertyWithName:(NSString *)name attributes:(FLEXPropertyAttributes *)attributes;

/// 如果实例是通过 \c +propertyWithName:attributes 创建的，则为 \c 0，
/// 否则这是 \c objc_properties 中的第一个属性
@property (nonatomic, readonly) objc_property_t  objc_property;
@property (nonatomic, readonly) objc_property_t  *objc_properties;
@property (nonatomic, readonly) NSInteger        objc_propertyCount;
@property (nonatomic, readonly) BOOL             isClassProperty;

/// 属性的名称。
@property (nonatomic, readonly) NSString         *name;
/// 属性的类型。从属性中获取完整类型。
@property (nonatomic, readonly) FLEXTypeEncoding type;
/// 属性的特性。
@property (nonatomic          ) FLEXPropertyAttributes *attributes;
/// （可能的）setter，无论属性是否为只读。
/// 例如，这可能是自定义setter。
@property (nonatomic, readonly) SEL likelySetter;
@property (nonatomic, readonly) NSString *likelySetterString;
/// 除非使用拥有类进行初始化，否则无效。
@property (nonatomic, readonly) BOOL likelySetterExists;
/// （可能的）getter。例如，这可能是自定义getter。
@property (nonatomic, readonly) SEL likelyGetter;
@property (nonatomic, readonly) NSString *likelyGetterString;
/// 除非使用拥有类进行初始化，否则无效。
@property (nonatomic, readonly) BOOL likelyGetterExists;
/// 对于类属性始终为 \c nil。
@property (nonatomic, readonly) NSString *likelyIvarName;
/// 除非使用拥有类进行初始化，否则无效。
@property (nonatomic, readonly) BOOL likelyIvarExists;

/// 是否肯定存在此属性的多个定义，
/// 例如在其他二进制映像中的分类或其他内容中。
/// @return \c objc_property 是否与 \c class_getProperty 的返回值匹配，
/// 如果此属性不是用 \c property:onClass 创建的，则为 \c NO
@property (nonatomic, readonly) BOOL multiple;
/// @return 包含此属性定义的映像的包，
/// 如果此属性不是用 \c property:onClass 创建的，或者
/// 如果此属性可能是在运行时定义的，则为 \c nil。
@property (nonatomic, readonly) NSString *imageName;
/// 包含此属性定义的映像的完整路径，
/// 如果此属性不是用 \c property:onClass 创建的，或者
/// 如果此属性可能是在运行时定义的，则为 \c nil。
@property (nonatomic, readonly) NSString *imagePath;

/// 内部使用
@property (nonatomic) id tag;

/// @return 通过 \c -valueForKey: 给出的 \c target 上此属性的值
/// 属性的源代码样式描述，包含所有特性。
@property (nonatomic, readonly) NSString *fullDescription;

/// 如果这是一个类属性，你必须传递类对象。
- (id)getValue:(id)target;
/// 调用 -getValue: 并将该值传递到
/// -[FLEXRuntimeUtility potentiallyUnwrapBoxedPointer:type:]
/// 并返回结果。
///
/// 如果这是一个类属性，你必须传递类对象。
- (id)getPotentiallyUnboxedValue:(id)target;

/// 无论 \c FLEXProperty 实例如何初始化，都可以安全使用。
///
/// 如果存在 \c self.objc_property，则使用它，否则使用 \c self.attributes
- (objc_property_attribute_t *)copyAttributesList:(unsigned int *)attributesCount;

/// 使用 \c self.attributes 中的特性
/// 替换给定类中当前属性的特性
///
/// 当属性不存在时会发生什么情况没有文档记录。
- (void)replacePropertyOnClass:(Class)cls;

#pragma mark 便捷的getter和setter
/// @return 具有给定实现的属性的getter。
/// @discussion 考虑使用 \c FLEXPropertyGetter 宏。
- (FLEXMethodBase *)getterWithImplementation:(IMP)implementation;
/// @return 具有给定实现的属性的setter。
/// @discussion 考虑使用 \c FLEXPropertySetter 宏。
- (FLEXMethodBase *)setterWithImplementation:(IMP)implementation;

#pragma mark FLEXMethod 属性 getter / setter 宏
// 在大多数情况下比自己使用上述方法更容易

/// 接受一个 \c FLEXProperty 和一个类型（例如 \c NSUInteger 或 \c id）并
/// 使用 \c FLEXProperty 的 \c attribute 的 \c backingIvarName 获取Ivar。
#define FLEXPropertyGetter(FLEXProperty, type) [FLEXProperty \
    getterWithImplementation:imp_implementationWithBlock(^(id self) { \
        return *(type *)[self getIvarAddressByName:FLEXProperty.attributes.backingIvar]; \
    }) \
];
/// 接受一个 \c FLEXProperty 和一个类型（例如 \c NSUInteger 或 \c id）并
/// 使用 \c FLEXProperty 的 \c attribute 的 \c backingIvarName 设置Ivar。
#define FLEXPropertySetter(FLEXProperty, type) [FLEXProperty \
    setterWithImplementation:imp_implementationWithBlock(^(id self, type value) { \
        [self setIvarByName:FLEXProperty.attributes.backingIvar value:&value size:sizeof(type)]; \
    }) \
];
/// 接受一个 \c FLEXProperty、一个类型（例如 \c NSUInteger 或 \c id）和一个Ivar名称字符串来获取Ivar。
#define FLEXPropertyGetterWithIvar(FLEXProperty, ivarName, type) [FLEXProperty \
    getterWithImplementation:imp_implementationWithBlock(^(id self) { \
        return *(type *)[self getIvarAddressByName:ivarName]; \
    }) \
];
/// 接受一个 \c FLEXProperty、一个类型（例如 \c NSUInteger 或 \c id）和一个Ivar名称字符串来设置Ivar。
#define FLEXPropertySetterWithIvar(FLEXProperty, ivarName, type) [FLEXProperty \
    setterWithImplementation:imp_implementationWithBlock(^(id self, type value) { \
        [self setIvarByName:ivarName value:&value size:sizeof(type)]; \
    }) \
];

@end
