//
//  FacebookSettingViewController.h
//  tottepost
//
//  Created by ISHITOYA Kentaro on 11/12/12.
//  Copyright (c) 2011 cocotomo. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "FBConnect.h"
#import "PhotoSubmitterProtocol.h"

@interface FacebookSettingTableViewController : UITableViewController<PhotoSubmitterAlbumDelegate>{
    int selectedAlbumIndex_;
}
@end
