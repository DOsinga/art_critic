//
//  ViewController.h
//  ArtCritic
//
//  Created by Douwe Osinga on 9/17/16.
//  Copyright © 2016 Douwe Osinga. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

#include <memory>
#include "tensorflow/core/public/session.h"

@interface ViewController : UIViewController {
    std::unique_ptr<tensorflow::Session> tf_session;
    std::vector<std::string> labels;
    
}

- (IBAction)unwindToList:(UIStoryboardSegue *)segue;


@end

