//
//  PTTableContentViewController.m
//  PTDatabaseReader
//
//  由 Peng Tao 创建于 15/11/23.
//  版权所有 © 2015年 Peng Tao. 保留所有权利。
//

#import "FLEXTableContentViewController.h"
#import "FLEXTableRowDataViewController.h"
#import "FLEXMultiColumnTableView.h"
#import "FLEXWebViewController.h"
#import "FLEXUtility.h"
#import "UIBarButtonItem+FLEX.h"

@interface FLEXTableContentViewController () <
    FLEXMultiColumnTableViewDataSource, FLEXMultiColumnTableViewDelegate
>
@property (nonatomic, readonly) NSArray<NSString *> *columns;
@property (nonatomic) NSMutableArray<NSArray *> *rows;
@property (nonatomic, readonly) NSString *tableName;
@property (nonatomic, nullable) NSMutableArray<NSString *> *rowIDs;
@property (nonatomic, readonly, nullable) id<FLEXDatabaseManager> databaseManager;

@property (nonatomic, readonly) BOOL canRefresh;

@property (nonatomic) FLEXMultiColumnTableView *multiColumnView;
@end

@implementation FLEXTableContentViewController

+ (instancetype)columns:(NSArray<NSString *> *)columnNames
                   rows:(NSArray<NSArray<NSString *> *> *)rowData
                 rowIDs:(NSArray<NSString *> *)rowIDs
              tableName:(NSString *)tableName
               database:(id<FLEXDatabaseManager>)databaseManager {
    return [[self alloc]
        initWithColumns:columnNames
        rows:rowData
        rowIDs:rowIDs
        tableName:tableName
        database:databaseManager
    ];
}

+ (instancetype)columns:(NSArray<NSString *> *)cols
                   rows:(NSArray<NSArray<NSString *> *> *)rowData {
    return [[self alloc] initWithColumns:cols rows:rowData rowIDs:nil tableName:nil database:nil];
}

- (instancetype)initWithColumns:(NSArray<NSString *> *)columnNames
                           rows:(NSArray<NSArray<NSString *> *> *)rowData
                         rowIDs:(nullable NSArray<NSString *> *)rowIDs
                      tableName:(nullable NSString *)tableName
                       database:(nullable id<FLEXDatabaseManager>)databaseManager {
    // 必须提供所有可选参数，或者一个都不提供
    BOOL all = rowIDs && tableName && databaseManager;
    BOOL none = !rowIDs && !tableName && !databaseManager;
    NSParameterAssert(all || none);

    self = [super init];
    if (self) {
        self->_columns = columnNames.copy;
        self->_rows = rowData.mutableCopy;
        self->_rowIDs = rowIDs.mutableCopy;
        self->_tableName = tableName.copy;
        self->_databaseManager = databaseManager;
    }

    return self;
}

- (void)loadView {
    [super loadView];
    
    [self.view addSubview:self.multiColumnView];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.tableName;
    [self.multiColumnView reloadData];
    [self setupToolbarItems];
}

- (FLEXMultiColumnTableView *)multiColumnView {
    if (!_multiColumnView) {
        _multiColumnView = [[FLEXMultiColumnTableView alloc]
            initWithFrame:FLEXRectSetSize(CGRectZero, self.view.frame.size)
        ];
        
        _multiColumnView.dataSource = self;
        _multiColumnView.delegate   = self;
    }
    
    return _multiColumnView;
}

- (BOOL)canRefresh {
    return self.databaseManager && self.tableName;
}

#pragma mark MultiColumnTableView DataSource

- (NSInteger)numberOfColumnsInTableView:(FLEXMultiColumnTableView *)tableView {
    return self.columns.count;
}

- (NSInteger)numberOfRowsInTableView:(FLEXMultiColumnTableView *)tableView {
    return self.rows.count;
}

- (NSString *)columnTitle:(NSInteger)column {
    return self.columns[column];
}

- (NSString *)rowTitle:(NSInteger)row {
    return @(row).stringValue;
}

- (NSArray *)contentForRow:(NSInteger)row {
    return self.rows[row];
}

- (CGFloat)multiColumnTableView:(FLEXMultiColumnTableView *)tableView
      heightForContentCellInRow:(NSInteger)row {
    return 40;
}

- (CGFloat)multiColumnTableView:(FLEXMultiColumnTableView *)tableView
    minWidthForContentCellInColumn:(NSInteger)column {
    return 100;
}

- (CGFloat)heightForTopHeaderInTableView:(FLEXMultiColumnTableView *)tableView {
    return 40;
}

- (CGFloat)widthForLeftHeaderInTableView:(FLEXMultiColumnTableView *)tableView {
    NSString *str = [NSString stringWithFormat:@"%lu",(unsigned long)self.rows.count];
    NSDictionary *attrs = @{ NSFontAttributeName : [UIFont systemFontOfSize:17.0] };
    CGSize size = [str boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, 14)
        options:NSStringDrawingUsesLineFragmentOrigin
        attributes:attrs context:nil
    ].size;
    
    return size.width + 20;
}


#pragma mark MultiColumnTableView Delegate

- (void)multiColumnTableView:(FLEXMultiColumnTableView *)tableView didSelectRow:(NSInteger)row {
    NSArray<NSString *> *fields = [self.rows[row] flex_mapped:^id(NSString *field, NSUInteger idx) {
        return [NSString stringWithFormat:@"%@:\n%@", self.columns[idx], field];
    }];
    
    NSArray<NSString *> *values = [self.rows[row] flex_mapped:^id(NSString *value, NSUInteger idx) {
        return [NSString stringWithFormat:@"'%@'", value];
    }];
    
    [FLEXAlert makeAlert:^(FLEXAlert *make) {
        make.title([@"行 " stringByAppendingString:@(row).stringValue]);
        NSString *message = [fields componentsJoinedByString:@"\n\n"];
        make.message(message);
        make.button(@"复制").handler(^(NSArray<NSString *> *strings) {
            UIPasteboard.generalPasteboard.string = message;
        });
        make.button(@"复制为CSV").handler(^(NSArray<NSString *> *strings) {
            UIPasteboard.generalPasteboard.string = [values componentsJoinedByString:@", "];
        });
        make.button(@"专注于行").handler(^(NSArray<NSString *> *strings) {
            UIViewController *focusedRow = [FLEXTableRowDataViewController
                rows:[NSDictionary dictionaryWithObjects:self.rows[row] forKeys:self.columns]
            ];
            [self.navigationController pushViewController:focusedRow animated:YES];
        });
        
        // 删除行的选项
        BOOL hasRowID = self.rows.count && row < self.rows.count;
        if (hasRowID && self.canRefresh) {
            make.button(@"删除").destructiveStyle().handler(^(NSArray<NSString *> *strings) {
                NSString *deleteRow = [NSString stringWithFormat:
                    @"DELETE FROM %@ WHERE rowid = %@",
                    self.tableName, self.rowIDs[row]
                ];
                
                [self executeStatementAndShowResult:deleteRow completion:^(BOOL success) {
                    // 移除已删除的行并重新加载视图
                    if (success) {
                        [self reloadTableDataFromDB];
                    }
                }];
            });
        }
        
        make.button(@"关闭").cancelStyle();
    } showFrom:self];
}

- (void)multiColumnTableView:(FLEXMultiColumnTableView *)tableView
    didSelectHeaderForColumn:(NSInteger)column
                    sortType:(FLEXTableColumnHeaderSortType)sortType {
    
    NSArray<NSArray *> *sortContentData = [self.rows
        sortedArrayWithOptions:NSSortStable
        usingComparator:^NSComparisonResult(NSArray *obj1, NSArray *obj2) {
            id a = obj1[column], b = obj2[column];
            if (a == NSNull.null) {
                return NSOrderedAscending;
            }
            if (b == NSNull.null) {
                return NSOrderedDescending;
            }
        
            if ([a respondsToSelector:@selector(compare:options:)] &&
                [b respondsToSelector:@selector(compare:options:)]) {
                return [a compare:b options:NSNumericSearch];
            }
            
            if ([a respondsToSelector:@selector(compare:)] && [b respondsToSelector:@selector(compare:)]) {
                return [a compare:b];
            }
            
            return NSOrderedSame;
        }
    ];
    
    if (sortType == FLEXTableColumnHeaderSortTypeDesc) {
        sortContentData = sortContentData.reverseObjectEnumerator.allObjects.copy;
    }
    
    self.rows = sortContentData.mutableCopy;
    [self.multiColumnView reloadData];
}

#pragma mark - About Transition

- (void)willTransitionToTraitCollection:(UITraitCollection *)newCollection
              withTransitionCoordinator:(id <UIViewControllerTransitionCoordinator>)coordinator {
    [super willTransitionToTraitCollection:newCollection withTransitionCoordinator:coordinator];
    
    [coordinator animateAlongsideTransition:^(id <UIViewControllerTransitionCoordinatorContext> context) {
        if (newCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact) {
            self.multiColumnView.frame = CGRectMake(0, 32, self.view.frame.size.width, self.view.frame.size.height - 32);
        }
        else {
            self.multiColumnView.frame = CGRectMake(0, 64, self.view.frame.size.width, self.view.frame.size.height - 64);
        }
        
        [self.view setNeedsLayout];
    } completion:nil];
}

#pragma mark - Toolbar

- (void)setupToolbarItems {
    // 我们不支持修改 realm 数据库
    if (![self.databaseManager respondsToSelector:@selector(executeStatement:)]) {
        return;
    }
    
    UIBarButtonItem *trashButton = FLEXBarButtonItemSystem(Trash, self, @selector(trashPressed));
    UIBarButtonItem *addButton = FLEXBarButtonItemSystem(Add, self, @selector(addPressed));

    // 只有当我们有表名时才允许添加或删除行
    trashButton.enabled = self.canRefresh;
    addButton.enabled = self.canRefresh;
    
    self.toolbarItems = @[
        UIBarButtonItem.flex_flexibleSpace,
        addButton,
        UIBarButtonItem.flex_flexibleSpace,
        [trashButton flex_withTintColor:UIColor.redColor],
    ];
}

- (void)trashPressed {
    NSParameterAssert(self.tableName);

    [FLEXAlert makeAlert:^(FLEXAlert *make) {
        make.title(@"删除所有行");
        make.message(@"此表中的所有行都将被永久删除。\n你想继续吗？");
        
        make.button(@"是的，我确定").destructiveStyle().handler(^(NSArray<NSString *> *strings) {
            NSString *deleteAll = [NSString stringWithFormat:@"DELETE FROM %@", self.tableName];
            [self executeStatementAndShowResult:deleteAll completion:^(BOOL success) {
                // 只在成功时关闭
                if (success) {
                    [self.navigationController popViewControllerAnimated:YES];
                }
            }];
        });
        make.button(@"取消").cancelStyle();
    } showFrom:self];
}

- (void)addPressed {
    NSParameterAssert(self.tableName);

    [FLEXAlert makeAlert:^(FLEXAlert *make) {
        make.title(@"添加一个新行");
        make.message(@"在INSERT语句中使用的逗名分隔值。\n\n");
        make.message(@"插入[表]值（your_input）");
        make.textField(@"5, 'John Smith', 14,...");
        make.button(@"插入").handler(^(NSArray<NSString *> *strings) {
            NSString *statement = [NSString stringWithFormat:
                @"INSERT INTO %@ VALUES (%@)", self.tableName, strings[0]
            ];

            [self executeStatementAndShowResult:statement completion:^(BOOL success) {
                if (success) {
                    [self reloadTableDataFromDB];
                }
            }];
        });
        make.button(@"取消").cancelStyle();
    } showFrom:self];
}

#pragma mark - Helpers

- (void)executeStatementAndShowResult:(NSString *)statement
                           completion:(void (^_Nullable)(BOOL success))completion {
    NSParameterAssert(self.databaseManager);

    FLEXSQLResult *result = [self.databaseManager executeStatement:statement];
    
    [FLEXAlert makeAlert:^(FLEXAlert *make) {
        if (result.isError) {
            make.title(@"错误");
        }
        
        make.message(result.message ?: @"<无输出>");
        make.button(@"关闭").cancelStyle().handler(^(NSArray<NSString *> *_) {
            if (completion) {
                completion(!result.isError);
            }
        });
    } showFrom:self];
}

- (void)reloadTableDataFromDB {
    if (!self.canRefresh) {
        return;
    }

    NSArray<NSArray *> *rows = [self.databaseManager queryAllDataInTable:self.tableName];
    NSArray<NSString *> *rowIDs = nil;
    if ([self.databaseManager respondsToSelector:@selector(queryRowIDsInTable:)]) {
        rowIDs = [self.databaseManager queryRowIDsInTable:self.tableName];
    }

    self.rows = rows.mutableCopy;
    self.rowIDs = rowIDs.mutableCopy;
    [self.multiColumnView reloadData];
}

@end
