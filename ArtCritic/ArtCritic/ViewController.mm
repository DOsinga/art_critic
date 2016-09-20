//
//  ViewController.mm
//  ArtCritic
//
//  Created by Douwe Osinga on 9/17/16.
//  Copyright © 2016 Douwe Osinga. All rights reserved.
//

#import "ViewController.h"
#include "tensorflow_utils.h"
#import <ImageIO/CGImageProperties.h>

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UIView *viewCameraPreview;
@property (weak, nonatomic) IBOutlet UIButton *buttonAnalyze;
@property (weak, nonatomic) IBOutlet UILabel *labelExplain;
@property (weak, nonatomic) IBOutlet UIView *viewBottom;
@property (weak, nonatomic) IBOutlet UILabel *labelLoadingModel;
@property (weak, nonatomic) IBOutlet UIImageView *imageDebug;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *spinner;
@property (weak, nonatomic) IBOutlet UILabel *labelResults;

@property(nonatomic, strong) AVCaptureStillImageOutput *stillImageOutput;
@property(nonatomic, strong) AVCaptureVideoDataOutput *videoDataOutput;
@property(nonatomic, strong) dispatch_queue_t videoDataOutputQueue;
@property(nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property(nonatomic) Boolean isAnalyzing;
@end

@implementation ViewController {
}


- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self.spinner startAnimating];
    
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
            self.spinner.hidden = TRUE;
            self.labelLoadingModel.hidden = TRUE;
            [self setupAVCapture];
            LOG(INFO) << "Done!";
        });
    });
}

- (void)setupAVCapture {
    NSError *error = nil;

    self.session = [AVCaptureSession new];
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
        [self.session setSessionPreset:AVCaptureSessionPreset640x480];
    else
        [self.session setSessionPreset:AVCaptureSessionPresetPhoto];

    AVCaptureDevice *device =
            [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    AVCaptureDeviceInput *deviceInput =
            [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    assert(error == nil);

    if ([_session canAddInput:deviceInput]) [_session addInput:deviceInput];

    self.stillImageOutput = [AVCaptureStillImageOutput new];
/*    [self.stillImageOutput
            addObserver:self
             forKeyPath:@"capturingStillImage"
                options:NSKeyValueObservingOptionNew
                context:(void *)(AVCaptureStillImageIsCapturingStillImageContext)];
*/
    if ([_session canAddOutput:self.stillImageOutput])
        [_session addOutput:self.stillImageOutput];

    self.videoDataOutput = [AVCaptureVideoDataOutput new];

    NSDictionary *rgbOutputSettings = @{(id) kCVPixelBufferPixelFormatTypeKey : @(kCMPixelFormat_32BGRA)};
    [self.videoDataOutput setVideoSettings:rgbOutputSettings];
    [self.videoDataOutput setAlwaysDiscardsLateVideoFrames:YES];
    self.videoDataOutputQueue = dispatch_queue_create("VideoDataOutputQueue", DISPATCH_QUEUE_SERIAL);
    //[self.videoDataOutput setSampleBufferDelegate:self queue:self.videoDataOutputQueue];

    if ([_session canAddOutput:self.videoDataOutput])
        [_session addOutput:self.videoDataOutput];
    [[self.videoDataOutput connectionWithMediaType:AVMediaTypeVideo] setEnabled:YES];

    self.previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.session];
    [self.previewLayer setBackgroundColor:[[UIColor blackColor] CGColor]];
    [self.previewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
    CALayer *rootLayer = [self.viewCameraPreview layer];
    [rootLayer setMasksToBounds:YES];
    [self.previewLayer setFrame:[rootLayer bounds]];
    [rootLayer addSublayer:self.previewLayer];
    [self.session startRunning];

    if (error) {
        UIAlertView *alertView = [[UIAlertView alloc]
                initWithTitle:[NSString stringWithFormat:@"Failed with error %d",
                                                         (int)[error code]]
                      message:[error localizedDescription]
                     delegate:nil
            cancelButtonTitle:@"Dismiss"
            otherButtonTitles:nil];
        [alertView show];
        [self teardownAVCapture];
    }
}

-(IBAction) captureNow {
    self.isAnalyzing = !self.isAnalyzing;
    if (self.isAnalyzing) {
        for (AVCaptureConnection *connection in self.stillImageOutput.connections) {
            for (AVCaptureInputPort *port in [connection inputPorts]) {
                if ([[port mediaType] isEqual:AVMediaTypeVideo] ) {
                    [self.stillImageOutput captureStillImageAsynchronouslyFromConnection:connection
                                                                       completionHandler: ^(CMSampleBufferRef imageSampleBuffer, NSError *error) {
                                                                           NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageSampleBuffer];
                                                                           UIImage *image = [[UIImage alloc] initWithData:imageData];
                                                                           NSLog(@"Image %f x %f", image.size.width, image.size.height);
                                                                           [self recognizeImage:image];
                                                                       }];
                    return;
                }
            }
        }
        NSLog(@"No fitting device found. Very odd.");
    } else {
        self.labelExplain.hidden = FALSE;
        self.buttonAnalyze.enabled = TRUE;
        self.labelResults.hidden = TRUE;
        self.imageDebug.hidden = TRUE;
        self.previewLayer.hidden = FALSE;
        [self.session startRunning];
    }
}

- (CVPixelBufferRef)pixelBufferFromCGImage:(CGImageRef)image {
    // from: http://stackoverflow.com/questions/8138018/convert-uiimage-to-cvimagebufferref
    CGSize frameSize = CGSizeMake(CGImageGetWidth(image), CGImageGetHeight(image));
    NSDictionary *options = @{
            (__bridge NSString *)kCVPixelBufferCGImageCompatibilityKey: @(NO),
            (__bridge NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @(NO)
    };
    CVPixelBufferRef pixelBuffer;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, frameSize.width,
            frameSize.height,  kCVPixelFormatType_32ARGB, (__bridge CFDictionaryRef) options,
            &pixelBuffer);
    if (status != kCVReturnSuccess) {
        return NULL;
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    void *data = CVPixelBufferGetBaseAddress(pixelBuffer);
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(data, frameSize.width, frameSize.height,
            8, CVPixelBufferGetBytesPerRow(pixelBuffer), rgbColorSpace,
            (CGBitmapInfo) kCGImageAlphaNoneSkipLast);
    CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(image),
            CGImageGetHeight(image)), image);
    CGColorSpaceRelease(rgbColorSpace);
    CGContextRelease(context);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

    return pixelBuffer;
}

- (void)teardownAVCapture {
    [self.previewLayer removeFromSuperlayer];
}

- (void)recognizeImage:(UIImage *)image {

    CGFloat minSize = MIN(image.size.width, image.size.height);
    CGRect cropRect = CGRectMake((image.size.width - minSize) / 2, (image.size.height - minSize) / 2, minSize, minSize);
    
    CGAffineTransform rectTransform;
    switch (image.imageOrientation) {
        case UIImageOrientationLeft:
            rectTransform = CGAffineTransformTranslate(CGAffineTransformMakeRotation(M_PI_2), 0, -image.size.height);
            break;
        case UIImageOrientationRight:
            rectTransform = CGAffineTransformTranslate(CGAffineTransformMakeRotation(-M_PI_2), -image.size.width, 0);
            break;
        case UIImageOrientationDown:
            rectTransform = CGAffineTransformTranslate(CGAffineTransformMakeRotation(-M_PI), -image.size.width, -image.size.height);
            break;
        default:
            rectTransform = CGAffineTransformIdentity;
    };
    rectTransform = CGAffineTransformScale(rectTransform, image.scale, image.scale);
    
    CGImageRef imageRef = CGImageCreateWithImageInRect([image CGImage], CGRectApplyAffineTransform(cropRect, rectTransform));
    UIImage *cropped = [UIImage imageWithCGImage:imageRef scale:image.scale orientation:image.imageOrientation];
    CGImageRelease(imageRef);
    
    self.imageDebug.image = cropped;
    self.imageDebug.hidden = TRUE;

    [self.session stopRunning];
    self.spinner.hidden = FALSE;
    [self.spinner startAnimating];
    [self.viewCameraPreview bringSubviewToFront:self.spinner];
    self.previewLayer.hidden = TRUE;

    self.labelLoadingModel.text = @"Analyzing picture";
    self.labelLoadingModel.textColor = [UIColor whiteColor];
    self.labelLoadingModel.hidden = FALSE;
    [self.viewCameraPreview bringSubviewToFront:self.labelLoadingModel];
    self.buttonAnalyze.enabled = FALSE;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSDictionary *labelsAndValues = [self runCNNOnFrame:cropped];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.spinner.hidden = TRUE;
            self.labelLoadingModel.hidden = TRUE;
            self.labelExplain.hidden = TRUE;
            self.imageDebug.hidden = FALSE;
            self.buttonAnalyze.enabled = TRUE;
            self.labelResults.hidden = FALSE;
            NSMutableString *res = [NSMutableString new];
            int count = 0;
            if (!labelsAndValues.count) {
                [res appendString:@"No results"];
                count = 1;
            } else {
                NSArray *sortedKeys = [labelsAndValues keysSortedByValueUsingComparator:^NSComparisonResult(id obj1, id obj2) {
                    return [obj2 compare:obj1];
                }];
                for (NSString *key in sortedKeys) {
                    int value = int(100 * [labelsAndValues[key] doubleValue]);
                    [res appendFormat:@"%@: %2d %%\n", key, value];
                    count += 1;
                    if (count == 3) {
                        break;
                    }
                }
            }
            self.labelResults.numberOfLines = count;
            self.labelResults.text = [res copy];
            [self.buttonAnalyze setTitle: @"Reset" forState: UIControlStateNormal];
        });
    });

}

- (NSDictionary *)runCNNOnFrame:(UIImage *)image {
    image = [UIImage imageNamed:@"IMG_5219.PNG"];
    CVPixelBufferRef pixelBuffer = [self pixelBufferFromCGImage:image.CGImage];
    assert(pixelBuffer != NULL);

    OSType sourcePixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
    int doReverseChannels;
    if (kCVPixelFormatType_32ARGB == sourcePixelFormat) {
        doReverseChannels = 1;
    } else if (kCVPixelFormatType_32BGRA == sourcePixelFormat) {
        doReverseChannels = 0;
    } else {
        assert(false);  // Unknown source format
    }

    const int sourceRowBytes = (int)CVPixelBufferGetBytesPerRow(pixelBuffer);
    const int image_width = (int)CVPixelBufferGetWidth(pixelBuffer);
    const int fullHeight = (int)CVPixelBufferGetHeight(pixelBuffer);
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    unsigned char *sourceBaseAddr =
            (unsigned char *)(CVPixelBufferGetBaseAddress(pixelBuffer));
    int image_height;
    unsigned char *sourceStartAddr;
    if (fullHeight <= image_width) {
        image_height = fullHeight;
        sourceStartAddr = sourceBaseAddr;
    } else {
        image_height = image_width;
        const int marginY = ((fullHeight - image_width) / 2);
        sourceStartAddr = (sourceBaseAddr + (marginY * sourceRowBytes));
    }
    const int image_channels = 4;

    const int wanted_width = 299;
    const int wanted_height = 299;
    const int wanted_channels = 3;
    const float input_mean = 128.0f;
    const float input_std = 128.0f;

    assert(image_channels >= wanted_channels);
    tensorflow::Tensor image_tensor(
            tensorflow::DT_FLOAT,
            tensorflow::TensorShape(
                    {1, wanted_height, wanted_width, wanted_channels}));
    auto image_tensor_mapped = image_tensor.tensor<float, 4>();
    tensorflow::uint8 *in = sourceStartAddr;
    float *out = image_tensor_mapped.data();
    for (int y = 0; y < wanted_height; ++y) {
        float *out_row = out + (y * wanted_width * wanted_channels);
        for (int x = 0; x < wanted_width; ++x) {
            const int in_x = (y * image_width) / wanted_width;
            const int in_y = (x * image_height) / wanted_height;
            tensorflow::uint8 *in_pixel =
                    in + (in_y * image_width * image_channels) + (in_x * image_channels);
            float *out_pixel = out_row + (x * wanted_channels);
            for (int c = 0; c < wanted_channels; ++c) {
                out_pixel[c] = (in_pixel[c] - input_mean) / input_std;
            }
        }
    }

    if (tf_session.get()) {
        std::string input_layer = "Mul";
        std::string output_layer = "final_result";
        std::vector<tensorflow::Tensor> outputs;
        tensorflow::Status run_status = tf_session->Run(
                {{input_layer, image_tensor}}, {output_layer}, {}, &outputs);
        if (!run_status.ok()) {
            LOG(ERROR) << "Running model failed:" << run_status;
        } else {
            tensorflow::Tensor *output = &outputs[0];
            auto predictions = output->flat<float>();

            NSMutableDictionary *newValues = [NSMutableDictionary dictionary];
            for (int index = 0; index < predictions.size(); index += 1) {
                const float predictionValue = predictions(index);
                if (predictionValue > 0.05f) {
                    std::string label = labels[index % predictions.size()];
                    NSString *labelObject = [NSString stringWithCString:label.c_str()];
                    newValues[labelObject] = @(predictionValue);
                    NSLog(@"Label %@: %f", labelObject, predictionValue);
                }
            }
            return [newValues copy];
        }
    }
    return nil;
}


- (IBAction)unwindToList:(UIStoryboardSegue *)segue {
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

@end
