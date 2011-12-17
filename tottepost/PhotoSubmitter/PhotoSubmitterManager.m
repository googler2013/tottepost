//
//  PhotoSubmitter.m
//  tottepost
//
//  Created by ISHITOYA Kentaro on 11/12/13.
//  Copyright (c) 2011 cocotomo. All rights reserved.
//

#import "PhotoSubmitterManager.h"
/*!
 * singleton instance
 */
static PhotoSubmitterManager* TottePostPhotoSubmitter;

//-----------------------------------------------------------------------------
//Private Implementations
//-----------------------------------------------------------------------------
@interface PhotoSubmitterManager(PrivateImplementation)
- (void) setupInitialState;
@end

@implementation PhotoSubmitterManager(PrivateImplementation)
-(void)setupInitialState{
    submitters_ = [[NSMutableDictionary alloc] init];
    supportedTypes_ = [NSMutableArray arrayWithObjects:
                     [NSNumber numberWithInt: PhotoSubmitterTypeFacebook],
                     [NSNumber numberWithInt: PhotoSubmitterTypeTwitter],
                     [NSNumber numberWithInt: PhotoSubmitterTypeFlickr], nil];
    [self loadSubmitters];
}
@end

//-----------------------------------------------------------------------------
//Public Implementations
//-----------------------------------------------------------------------------

@implementation PhotoSubmitterManager
@synthesize supportedTypes = supportedTypes_;

/*!
 * initializer
 */
- (id)init{
    self = [super init];
    if(self){
        [self setupInitialState];
    }
    return self;
}

/*!
 * get submitter
 */
- (id<PhotoSubmitterProtocol>)submitterForType:(PhotoSubmitterType)type{
    id <PhotoSubmitterProtocol> submitter = [submitters_ objectForKey:[NSNumber numberWithInt:type]];
    if(submitter){
        return submitter;
    }
    switch (type) {
        case PhotoSubmitterTypeFacebook:
            submitter = [[FacebookPhotoSubmitter alloc] init];
            break;
        case PhotoSubmitterTypeTwitter:
            break;
        case PhotoSubmitterTypeFlickr:
            submitter = [[FlickrPhotoSubmitter alloc] init];
            break;
        default:
            break;
    }
    if(submitter){
        [submitters_ setObject:submitter forKey:[NSNumber numberWithInt:type]];
    }
    return submitter;
}

/*!
 * submit photo to social app
 */
- (void)submitPhoto:(UIImage *)photo{
    [self submitPhoto:photo comment:nil];
}

/*!
 * submit photo with comment to social app
 */
- (void)submitPhoto:(UIImage *)photo comment:(NSString *)comment{
    for(NSNumber *key in submitters_){
        id<PhotoSubmitterProtocol> submitter = [submitters_ objectForKey:key];
        if([submitter isLogined]){
            [submitter submitPhoto:photo];
        }
    }
}

/*!
 * set authentication delegate to submitters
 */
- (void)setAuthenticationDelegate:(id<PhotoSubmitterAuthenticationDelegate>)delegate{
    for(NSNumber *key in submitters_){
        id<PhotoSubmitterProtocol> submitter = [submitters_ objectForKey:key];
        submitter.authDelegate = delegate;
    }
}

/*!
 * set photo delegate to submitters
 */
- (void)setPhotoDelegate:(id<PhotoSubmitterPhotoDelegate>)delegate{
    for(NSNumber *key in submitters_){
        id<PhotoSubmitterProtocol> submitter = [submitters_ objectForKey:key];
        submitter.photoDelegate = delegate;
    }
}

/*!
 * load selected submitters
 */
- (void)loadSubmitters{
    for (NSNumber *t in supportedTypes_){
        PhotoSubmitterType type = (PhotoSubmitterType)[t intValue];
        [self submitterForType:type];
    }
}

/*!
 * on url loaded
 */
- (BOOL)didOpenURL:(NSURL *)url{
    for(NSNumber *key in submitters_){
        id<PhotoSubmitterProtocol> submitter = [submitters_ objectForKey:key];
        if([submitter isProcessableURL:url]){
            return [submitter didOpenURL:url];
        }
    }
    return NO; 
}

#pragma mark -
#pragma mark static methods
/*!
 * singleton method
 */
+ (PhotoSubmitterManager *)getInstance{
    if(TottePostPhotoSubmitter == nil){
        TottePostPhotoSubmitter = [[PhotoSubmitterManager alloc]init];
    }
    return TottePostPhotoSubmitter;
}
/*!
 * get submitter
 */
+ (id<PhotoSubmitterProtocol>)submitterForType:(PhotoSubmitterType)type{
    return [[PhotoSubmitterManager getInstance] submitterForType:type];
}

/*!
 * get facebook photo submitter
 */
+ (FacebookPhotoSubmitter *)facebookPhotoSubmitter{
    return (FacebookPhotoSubmitter *)[[PhotoSubmitterManager getInstance] submitterForType:PhotoSubmitterTypeFacebook];
}
/*!
 * get facebook photo submitter
 */
+ (FlickrPhotoSubmitter *)flickrPhotoSubmitter{
    return (FlickrPhotoSubmitter *)[[PhotoSubmitterManager getInstance] submitterForType:PhotoSubmitterTypeFlickr];
}
@end
