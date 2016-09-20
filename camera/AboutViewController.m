//
//  AboutViewController.m
//  ArtCritic
//
//  Created by Douwe Osinga on 9/18/16.
//  Copyright © 2016 Douwe Osinga. All rights reserved.
//

#import "AboutViewController.h"
#import <UIKit/UIKit.h>

@interface AboutViewController ()
@property (weak, nonatomic) IBOutlet UIImageView *logoImage;
@property (weak, nonatomic) IBOutlet UILabel *introText;
@property (weak, nonatomic) IBOutlet UITextView *acknowledgements;

@end

@implementation AboutViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewDidLayoutSubviews {
    while (TRUE) {
        self.introText.frame = CGRectMake(self.introText.frame.origin.x,
                                          self.introText.frame.origin.y,
                                          self.view.bounds.size.width - self.logoImage.bounds.size.width - 40,
                                          0);
        [self.introText sizeToFit];
        [self.introText setNeedsDisplay];
        if (self.introText.frame.size.height < self.logoImage.frame.size.height) {
            break;
        }
        self.introText.font = [self.introText.font fontWithSize:self.introText.font.pointSize - 1.0];
    }
    
    NSArray *tuples = @[@[@"Wikipedia", @"https://www.wikipedia.org"],
                        @[@"TensorFlow", @"https://www.wikipedia.org"]
                        ];
    NSString *str = [self.acknowledgements.attributedText string];
    NSMutableAttributedString *attributedText = [[NSMutableAttributedString alloc] initWithAttributedString:self.acknowledgements.attributedText];
    for (NSArray *tuple in tuples) {
        NSRange r = [str rangeOfString:tuple[0]];
        if (r.location != NSNotFound) {
            [attributedText addAttribute:NSLinkAttributeName value:tuple[1] range:r];
        }
    }
    
    self.acknowledgements.linkTextAttributes = @{NSForegroundColorAttributeName : [UIColor blueColor],
                                                 NSUnderlineStyleAttributeName : @(NSUnderlineStyleSingle)};
    self.acknowledgements.attributedText = attributedText;
    self.acknowledgements.font = self.introText.font;
    self.acknowledgements.frame = CGRectMake(self.acknowledgements.frame.origin.x,
                                                 self.acknowledgements.frame.origin.y,
                                                 self.view.bounds.size.width - 20,
                                             0);
    [self.acknowledgements sizeToFit];
    [self.acknowledgements setNeedsDisplay];
    
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
