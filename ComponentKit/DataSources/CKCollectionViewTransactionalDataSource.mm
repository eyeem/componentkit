/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import "CKCollectionViewTransactionalDataSource.h"

#import "CKCollectionViewDataSourceCell.h"
#import "CKTransactionalComponentDataSourceConfiguration.h"
#import "CKTransactionalComponentDataSourceListener.h"
#import "CKTransactionalComponentDataSourceItem.h"
#import "CKTransactionalComponentDataSourceState.h"
#import "CKTransactionalComponentDataSourceAppliedChanges.h"
#import "CKComponentRootView.h"
#import "CKComponentLayout.h"
#import "CKComponentDataSourceAttachController.h"

@interface CKCollectionViewTransactionalDataSource () <
UICollectionViewDataSource,
CKTransactionalComponentDataSourceListener
>
{
  CKTransactionalComponentDataSource *_componentDataSource;
  __weak id<CKSupplementaryViewDataSource> _supplementaryViewDataSource;
  CKTransactionalComponentDataSourceState *_currentState;
  CKComponentDataSourceAttachController *_attachController;
}
@end

@implementation CKCollectionViewTransactionalDataSource
@synthesize supplementaryViewDataSource = _supplementaryViewDataSource;

- (instancetype)initWithCollectionView:(UICollectionView *)collectionView
           supplementaryViewDataSource:(id<CKSupplementaryViewDataSource>)supplementaryViewDataSource
                         configuration:(CKTransactionalComponentDataSourceConfiguration *)configuration
{
  self = [super init];
  if (self) {
    _componentDataSource = [[CKTransactionalComponentDataSource alloc] initWithConfiguration:configuration];
    [_componentDataSource addListener:self];
      
    _collectionView = collectionView;
    _collectionView.dataSource = self;
    [_collectionView registerClass:[CKCollectionViewDataSourceCell class] forCellWithReuseIdentifier:kReuseIdentifier];
    
    _attachController = [[CKComponentDataSourceAttachController alloc] init];
    _supplementaryViewDataSource = supplementaryViewDataSource;
  }
  return self;
}

#pragma mark - Changeset application

- (void)applyChangeset:(CKTransactionalComponentDataSourceChangeset *)changeset
                  mode:(CKUpdateMode)mode
              userInfo:(NSDictionary *)userInfo
{
  [_componentDataSource applyChangeset:changeset
                                  mode:mode
                              userInfo:userInfo];
}

static void applyChangesToCollectionView(CKTransactionalComponentDataSourceAppliedChanges *changes, UICollectionView *collectionView, CKTransactionalComponentDataSourceState *currentState, CKComponentDataSourceAttachController *attachController)
{
  [changes.updatedIndexPaths enumerateObjectsUsingBlock:^(NSIndexPath *indexPath, BOOL *stop) {
	if (CKCollectionViewDataSourceCell *cell = (CKCollectionViewDataSourceCell*) [collectionView cellForItemAtIndexPath:indexPath]) {
		_attachToCell(cell, indexPath, currentState, attachController);
	}
  }];
  [collectionView deleteItemsAtIndexPaths:[changes.removedIndexPaths allObjects]];
  [collectionView deleteSections:changes.removedSections];
  for (NSIndexPath *from in changes.movedIndexPaths) {
    NSIndexPath *to = changes.movedIndexPaths[from];
    [collectionView moveItemAtIndexPath:from toIndexPath:to];
  }
  [collectionView insertSections:changes.insertedSections];
  [collectionView insertItemsAtIndexPaths:[changes.insertedIndexPaths allObjects]];
}

#pragma mark - CKTransactionalComponentDataSourceListener

- (void)transactionalComponentDataSource:(CKTransactionalComponentDataSource *)dataSource
                  didModifyPreviousState:(CKTransactionalComponentDataSourceState *)previousState
                       byApplyingChanges:(CKTransactionalComponentDataSourceAppliedChanges *)changes
{
  [_collectionView performBatchUpdates:^{
    // Detach all the component layouts for items being deleted
    [self _detachComponentLayoutForRemovedItemsAtIndexPaths:[changes removedIndexPaths]
                                                    inState:previousState];
    // Update current state
    _currentState = [_componentDataSource state];
    applyChangesToCollectionView(changes, _collectionView, _currentState, _attachController);
  } completion:NULL];
}

- (void)_detachComponentLayoutForRemovedItemsAtIndexPaths:(NSSet *)removedIndexPaths
                                                  inState:(CKTransactionalComponentDataSourceState *)state
{
  for (NSIndexPath *indexPath in removedIndexPaths) {
    CKComponentScopeRootIdentifier identifier = [[[state objectAtIndexPath:indexPath] scopeRoot] globalIdentifier];
    [_attachController detachComponentLayoutWithScopeIdentifier:identifier];
  }
}

#pragma mark - State

- (id<NSObject>)modelForItemAtIndexPath:(NSIndexPath *)indexPath
{
  return [_currentState objectAtIndexPath:indexPath].model;
}

- (CGSize)sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
  return [_currentState objectAtIndexPath:indexPath].layout.size;
}

#pragma mark - Reload

- (void)reloadWithMode:(CKUpdateMode)mode
              userInfo:(NSDictionary *)userInfo
{
  [_componentDataSource reloadWithMode:mode userInfo:userInfo];
}

- (void)updateConfiguration:(CKTransactionalComponentDataSourceConfiguration *)configuration
                       mode:(CKUpdateMode)mode
                   userInfo:(NSDictionary *)userInfo
{
  [_componentDataSource updateConfiguration:configuration mode:mode userInfo:userInfo];
}

#pragma mark - UICollectionViewDataSource

static NSString *const kReuseIdentifier = @"com.component_kit.collection_view_data_source.cell";

static void _attachToCell(CKCollectionViewDataSourceCell *cell, NSIndexPath *indexPath, CKTransactionalComponentDataSourceState *currentState, CKComponentDataSourceAttachController *attachController)
{
  CKTransactionalComponentDataSourceItem *item = [currentState objectAtIndexPath:indexPath];
  [attachController attachComponentLayout:item.layout withScopeIdentifier:item.scopeRoot.globalIdentifier toView:cell.rootView];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
  CKCollectionViewDataSourceCell *cell = [_collectionView dequeueReusableCellWithReuseIdentifier:kReuseIdentifier forIndexPath:indexPath];
  _attachToCell(cell, indexPath, _currentState, _attachController);
  return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath
{
  return [_supplementaryViewDataSource collectionView:collectionView viewForSupplementaryElementOfKind:kind atIndexPath:indexPath];
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
  return _currentState ? [_currentState numberOfSections] : 0;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
  return _currentState ? [_currentState numberOfObjectsInSection:section] : 0;
}

@end
