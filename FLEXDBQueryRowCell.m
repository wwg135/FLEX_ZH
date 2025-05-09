//
//  FLEXDBQueryRowCell.m
//  FLEX
//
//  创建者：Peng Tao，日期：15/11/24.
//  版权所有 © 2015年 f。保留所有权利。
//
// 遇到问题联系中文翻译作者：pxx917144686

#import "FLEXDBQueryRowCell.h"
#import "FLEXMultiColumnTableView.h"
#import "NSArray+FLEX.h"
#import "UIFont+FLEX.h"
#import "FLEXColor.h"

NSString * const kFLEXDBQueryRowCellReuse = @"kFLEXDBQueryRowCellReuse";

@interface FLEXDBQueryRowCell ()
@property (nonatomic) NSInteger columnCount;
@property (nonatomic) NSArray<UILabel *> *labels;
@end

@implementation FLEXDBQueryRowCell

- (void)setData:(NSArray *)data {
    _data = data;
    self.columnCount = data.count;
    
    [self.labels flex_forEach:^(UILabel *label, NSUInteger idx) {
        id content = self.data[idx];
        
        if ([content isKindOfClass:[NSString class]]) {
            label.text = content;
        } else if (content == NSNull.null) {
            label.text = @"<null>"; // <null> 是特殊标记，保持不变
            label.textColor = FLEXColor.deemphasizedTextColor;
        } else {
            label.text = [content description];
        }
    }];
}

- (void)setColumnCount:(NSInteger)columnCount {
    if (columnCount != _columnCount) {
        _columnCount = columnCount;
        
        // 移除现有的标签
        for (UILabel *l in self.labels) {
            [l removeFromSuperview];
        }
        
        // 创建新的标签
        self.labels = [NSArray flex_forEachUpTo:columnCount map:^id(NSUInteger i) {
            UILabel *label = [UILabel new];
            label.font = UIFont.flex_defaultTableCellFont;
            label.textAlignment = NSTextAlignmentLeft;
            [self.contentView addSubview:label];
            
            return label;
        }];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    CGFloat height = self.contentView.frame.size.height;
    
    [self.labels flex_forEach:^(UILabel *label, NSUInteger i) {
        CGFloat width = [self.layoutSource dbQueryRowCell:self widthForColumn:i];
        CGFloat minX = [self.layoutSource dbQueryRowCell:self minXForColumn:i];
        label.frame = CGRectMake(minX + 5, 0, (width - 10), height);
    }];
}

@end
