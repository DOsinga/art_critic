//
//  ViewController.mm
//  ArtCritic
//
//  Created by Douwe Osinga on 9/17/16.
//  Copyright © 2016 Douwe Osinga. All rights reserved.
//

#import "ViewController.h"
#include "tensorflow_utils.h"

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UIView *viewCameraPreview;
@property (weak, nonatomic) IBOutlet UIButton *buttonAnalyze;
@property (weak, nonatomic) IBOutlet UILabel *labelExplain;
@property (weak, nonatomic) IBOutlet UIView *viewBottom;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    [self.viewCameraPreview addSubview:spinner];
    [spinner startAnimating];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        tensorflow::Status load_status = LoadModel(@"art_graph_quant", @"pb", &tf_session);
        if (!load_status.ok()) {
            LOG(FATAL) << "Couldn't load model: " << load_status;
        }
        
        tensorflow::Status labels_status = LoadLabels(@"art_graph_labels", @"txt", &labels);
        if (!labels_status.ok()) {
            LOG(FATAL) << "Couldn't load labels: " << labels_status;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [spinner stopAnimating];
            [spinner removeFromSuperview];
        });
    });

}

- (IBAction)unwindToList:(UIStoryboardSegue *)segue
{
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


- (void)viewDidLayoutSubviews {
    CGFloat size = self.view.bounds.size.width - self.viewCameraPreview.bounds.origin.x;
    self.viewCameraPreview.frame = CGRectMake(self.viewCameraPreview.bounds.origin.x,
                                              self.viewCameraPreview.bounds.origin.y + 20,
                                              size, size);
    CGFloat y = self.viewCameraPreview.bounds.origin.y + self.viewCameraPreview.bounds.size.height + 20;
    self.viewBottom.frame = CGRectMake(self.viewCameraPreview.bounds.origin.x, y,
                                       size, self.view.bounds.size.height - y);
    self.labelExplain.frame = CGRectMake(10, 10, size - 20, 0);
    [self.labelExplain sizeToFit];
    [self.labelExplain setNeedsDisplay];
    
    self.buttonAnalyze.frame = CGRectMake((self.viewBottom.bounds.size.width - self.buttonAnalyze.bounds.size.width) / 2,
                                          self.viewBottom.bounds.size.height - self.buttonAnalyze.bounds.size.height - 10,
                                          self.buttonAnalyze.bounds.size.width,
                                          self.buttonAnalyze.bounds.size.height);
    
}

@end
