//
//  AVFoundationCameraController.m
//  AVFoundationCameraController
//
//  Created by Kentaro ISHITOYA on 12/01/02.
//  Copyright (c) 2012 Kentaro ISHITOYA. All rights reserved.
//

#import <CoreMedia/CoreMedia.h>
#import <ImageIO/ImageIO.h>
#import "AVFoundationCameraController.h"
#import "UIImage+Resize.h"

#define INDICATOR_RECT_SIZE 50.0
#define PICKER_MAXIMUM_ZOOM_SCALE 5.0 
#define PICKER_PADDING_X 10
#define PICKER_PADDING_Y 10
#define PICKER_SHUTTER_BUTTON_WIDTH 60
#define PICKER_SHUTTER_BUTTON_HEIGHT 30
#define PICKER_FLASHMODE_BUTTON_WIDTH 60
#define PICKER_FLASHMODE_BUTTON_HEIGHT 30
#define PICKER_CAMERADEVICE_BUTTON_WIDTH 60
#define PICKER_CAMERADEVICE_BUTTON_HEIGHT 30

//-----------------------------------------------------------------------------
//Private Implementations
//-----------------------------------------------------------------------------
@interface AVFoundationCameraController(PrivateImplementation)
- (void) setupInitialState:(CGRect)frame;
- (void) initCamera:(AVCaptureDevice *)cameraDevice;
- (void) handleTapGesture: (UITapGestureRecognizer *)recognizer;
- (void) handlePinchGesture: (UIPinchGestureRecognizer *)recognizer;
- (void) handleShutterButtonTapped:(UIButton *)sender;
- (void) handleFlashModeButtonTapped:(UIButton *)sender;
- (void) handleCameraDeviceButtonTapped:(UIButton *)sender;
- (void) setFocus:(CGPoint)point;
- (void) autofocus;
- (void) updateCameraControls;
- (void) deviceOrientationDidChange;
- (NSData *) cropImageData:(NSData *)data withViewRect:(CGRect)viewRect andScale:(CGFloat)scale;
- (CGRect) normalizeCropRect:(CGRect)rect size:(CGSize)size;
@end

@implementation AVFoundationCameraController(PrivateImplementation)
/*!
 * initialize view
 */
-(void)setupInitialState:(CGRect)frame{
    self.view.frame = frame;
    pointOfInterest_ = CGPointMake(frame.size.width / 2, frame.size.height / 2);
    defaultBounds_ = frame;
    scale_ = 1.0;
    croppedViewRect_ = CGRectZero;
    
    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapGesture:)];
    tapRecognizer.delegate = self;
    [self.view addGestureRecognizer:tapRecognizer];
    UIPinchGestureRecognizer *pinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinchGesture:)];
    [self.view addGestureRecognizer:pinchRecognizer];
    
    shutterButton_ = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [shutterButton_ setTitle:@"Shutter" forState:UIControlStateNormal]; 
    [shutterButton_ addTarget:self action:@selector(handleShutterButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    flashModeButton_ = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [flashModeButton_ setTitle:@"Flash" forState:UIControlStateNormal];
    [flashModeButton_ addTarget:self action:@selector(handleFlashModeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    cameraDeviceButton_ = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [cameraDeviceButton_ setTitle:@"Device" forState:UIControlStateNormal];
    [cameraDeviceButton_ addTarget:self action:@selector(handleCameraDeviceButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    
    [self initCamera:self.backCameraDevice];
    showsCameraControls_ = YES;
    showsShutterButton_ = YES;
    useTapToFocus_ = YES;
    if(device_.isTorchAvailable){
        showsFlashModeButton_ = YES;
    }
    if(self.hasMultipleCameraDevices){
        showsCameraDeviceButton_ = YES;
    }
    [self updateCameraControls];
    
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deviceOrientationDidChange) name:@"UIDeviceOrientationDidChangeNotification" object:nil];
}

/*!
 * gesture recognizer delegate
 */
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if ([touch.view isKindOfClass:[UIButton class]]){
        return FALSE;
    }
    return TRUE;
}

/*!
 * initialize camera
 */
-(void)initCamera:(AVCaptureDevice *)cameraDevice{
    session_ = [[AVCaptureSession alloc] init];
    device_ = cameraDevice;
    NSError* error = nil;
    AVCaptureDeviceInput* videoInput =
    [AVCaptureDeviceInput deviceInputWithDevice:device_
                                          error:&error];
    if (!videoInput) {
        NSLog(@"%s|[ERROR] %@", __PRETTY_FUNCTION__, error);
        return;
    }
    
    [session_ addInput:videoInput];
    [session_ beginConfiguration];
    session_.sessionPreset = AVCaptureSessionPresetPhoto;
    [session_ commitConfiguration];
    
    [self autofocus];
    
    [device_ addObserver:self
              forKeyPath:@"adjustingExposure"
                 options:NSKeyValueObservingOptionNew
                 context:nil];
    
    imageOutput_ = [[AVCaptureStillImageOutput alloc] init];
    [session_ addOutput:imageOutput_];
    for (AVCaptureConnection* connection in imageOutput_.connections) {
        connection.videoOrientation = AVCaptureVideoOrientationPortrait;
    }
    
    previewLayer_ = [AVCaptureVideoPreviewLayer layerWithSession:session_];
    previewLayer_.automaticallyAdjustsMirroring = NO;
    previewLayer_.videoGravity = AVLayerVideoGravityResizeAspectFill;
    previewLayer_.frame = self.view.bounds;
    [self.view.layer addSublayer:previewLayer_];
    
    [session_ startRunning];
    
    // add layer
    indicatorLayer_ = [CALayer layer];
    indicatorLayer_.borderColor = [[UIColor whiteColor] CGColor];
    indicatorLayer_.borderWidth = 1.0;
    indicatorLayer_.frame = 
    CGRectMake(self.view.bounds.size.width/2.0 - INDICATOR_RECT_SIZE/2.0,
               self.view.bounds.size.height/2.0 - INDICATOR_RECT_SIZE/2.0,
               INDICATOR_RECT_SIZE,
               INDICATOR_RECT_SIZE);
    indicatorLayer_.hidden = NO;
    [self.view.layer addSublayer:indicatorLayer_];
    viewOrientation_ = UIDeviceOrientationPortrait;
    [self deviceOrientationDidChange];
}

/*!
 * update camera controls
 */
- (void)updateCameraControls{
    [shutterButton_ removeFromSuperview];
    [flashModeButton_ removeFromSuperview];
    [cameraDeviceButton_ removeFromSuperview];
    if(showsCameraControls_ == NO){
        return;
    }
    
    CGRect f = self.view.frame;
    if(showsShutterButton_ && [shutterButton_ isDescendantOfView:self.view] == NO){
        [shutterButton_ setFrame:CGRectMake((f.size.width - PICKER_SHUTTER_BUTTON_WIDTH) / 2    , f.size.height - PICKER_SHUTTER_BUTTON_HEIGHT - PICKER_PADDING_Y, PICKER_SHUTTER_BUTTON_WIDTH, PICKER_SHUTTER_BUTTON_HEIGHT)];
        [self.view addSubview: shutterButton_];
    }
    if(showsFlashModeButton_ && [flashModeButton_ isDescendantOfView:self.view] == NO){
        flashModeButton_.frame = CGRectMake(PICKER_PADDING_X, PICKER_PADDING_Y, PICKER_FLASHMODE_BUTTON_WIDTH, PICKER_FLASHMODE_BUTTON_HEIGHT);
        [self.view addSubview: flashModeButton_];
    }
    if(showsCameraDeviceButton_ && [cameraDeviceButton_ isDescendantOfView:self.view] == NO){        cameraDeviceButton_.frame = CGRectMake(f.size.width - PICKER_CAMERADEVICE_BUTTON_WIDTH - PICKER_PADDING_X, PICKER_PADDING_Y, PICKER_CAMERADEVICE_BUTTON_WIDTH, PICKER_CAMERADEVICE_BUTTON_HEIGHT);
        [self.view addSubview: cameraDeviceButton_];
    }
}

/*!
 * focus
 */
- (void) handleTapGesture:(UITapGestureRecognizer *)recognizer
{
    if(useTapToFocus_ == NO){
        return;
    }
    CGPoint point = [recognizer locationInView:self.view];
    
    indicatorLayer_.frame = CGRectMake(point.x - INDICATOR_RECT_SIZE /2.0,
                                       point.y - INDICATOR_RECT_SIZE /2.0,
                                       INDICATOR_RECT_SIZE,
                                       INDICATOR_RECT_SIZE);
    point.x = (point.x + fabs(previewLayer_.frame.origin.x)) / scale_;
    point.y = (point.y + fabs(previewLayer_.frame.origin.y)) / scale_;
    [self setFocus:point];
}

/*!
 * zoom
 */
- (void)handlePinchGesture:(UIPinchGestureRecognizer *)recognizer {
    CGFloat pinchScale = recognizer.scale;
    if(recognizer.state == UIGestureRecognizerStateBegan){
        lastPinchScale_ = pinchScale;
        return;
    }
    if(lastPinchScale_ == 0){
        lastPinchScale_ = pinchScale;
        return;
    }
    
    //calculate zoom scale
    CGFloat diff = (pinchScale - lastPinchScale_) * 2;
    CGFloat scale = scale_;
    if(diff > 0){
        scale += 0.05;
    }else{
        scale -= 0.05;
    }
    if(scale > PICKER_MAXIMUM_ZOOM_SCALE){
        scale = PICKER_MAXIMUM_ZOOM_SCALE;
    }else if(scale < 1.0){
        scale = 1.0;
    }
    if(scale_ == scale){
        return;
    }
    scale_ = scale;
    
    //calcurate zoom rect
    CGAffineTransform zt = CGAffineTransformScale(CGAffineTransformIdentity, scale_, scale_);
    CGRect rect = CGRectApplyAffineTransform(defaultBounds_, zt);
    
    if(CGPointEqualToPoint(pointOfInterest_, CGPointZero) || scale == 1.0){
        rect.origin.x = 0;
        rect.origin.y = 0;
    }else{
        rect.origin.x = -((pointOfInterest_.x * scale_) - defaultBounds_.size.width / 2);
        rect.origin.y = -((pointOfInterest_.y * scale_) - defaultBounds_.size.height / 2);
    }
    if(rect.origin.x > 0){
        rect.origin.x = 0;
    }
    if(rect.origin.y > 0){
        rect.origin.y = 0;
    }
    if(rect.origin.x + rect.size.width < defaultBounds_.size.width){
        rect.origin.x = defaultBounds_.size.width - rect.size.width;
    }
    if(rect.origin.y + rect.size.height < defaultBounds_.size.height){
        rect.origin.y = defaultBounds_.size.height - rect.size.height;
    }
    
    //calcurate indicator rect
    CGRect iframe = indicatorLayer_.frame;
    iframe.origin.x = (pointOfInterest_.x * scale_) - fabs(rect.origin.x) - INDICATOR_RECT_SIZE / 2.0;
    iframe.origin.y = (pointOfInterest_.y * scale_) - fabs(rect.origin.y) - INDICATOR_RECT_SIZE / 2.0;
    
    //set frame without animation
    [CATransaction begin];
    [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
    previewLayer_.frame = rect;    
    indicatorLayer_.frame = iframe;
    [CATransaction commit];
    lastPinchScale_ = pinchScale;
    
    if(scale == 1.0){
        croppedViewRect_ = CGRectZero;
    }else{
        croppedViewRect_ = CGRectMake(fabsf(rect.origin.x), fabsf(rect.origin.y), defaultBounds_.size.width, defaultBounds_.size.height);
    }
    
    if([self.delegate respondsToSelector:@selector(cameraController:didScaledTo:viewRect:)]){
        [self.delegate cameraController:self didScaledTo:scale_ viewRect:croppedViewRect_];
    }
}

/*!
 * autofocus
 */
- (void) autofocus{
    if (adjustingExposure_) {
        return;
    }
    NSError* error = nil;
    if ([device_ lockForConfiguration:&error] == NO) {
        NSLog(@"%s|[ERROR] %@", __PRETTY_FUNCTION__, error);
    }
    if ([device_ isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
        device_.focusMode = AVCaptureFocusModeContinuousAutoFocus;
        
    } else if ([device_ isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
        device_.focusMode = AVCaptureFocusModeAutoFocus;
    }
    
    if ([device_ isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
        device_.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
    } else if ([device_ isExposureModeSupported:AVCaptureExposureModeAutoExpose]) {
        device_.exposureMode = AVCaptureExposureModeAutoExpose;
    }
    
    if ([device_ isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance]) {
        device_.whiteBalanceMode = AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance;
    } else if ([device_ isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeAutoWhiteBalance]) {
        device_.whiteBalanceMode = AVCaptureWhiteBalanceModeAutoWhiteBalance;
    }
    [device_ unlockForConfiguration];
}

/*!
 * set focus and exposure point
 */
- (void)setFocus:(CGPoint)p
{
    CGSize viewSize = self.view.bounds.size;
    pointOfInterest_ = p;
    CGPoint pointOfInterest = CGPointMake(p.y / viewSize.height,
                                          1.0 - p.x / viewSize.width);
    
    NSError* error = nil;
    if ([device_ lockForConfiguration:&error] == NO) {
        NSLog(@"%s|[ERROR] %@", __PRETTY_FUNCTION__, error); 
    }
    
    if ([device_ isFocusPointOfInterestSupported] &&
        [device_ isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
        device_.focusPointOfInterest = pointOfInterest;
        device_.focusMode = AVCaptureFocusModeAutoFocus;
    }
    
    if ([device_ isExposurePointOfInterestSupported] &&
        [device_ isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]){
        adjustingExposure_ = YES;
        device_.exposurePointOfInterest = pointOfInterest;
        device_.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
    }
    
    [device_ unlockForConfiguration];
}

/*!
 * observe
 */
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (!adjustingExposure_) {
        return;
    }
    
	if ([keyPath isEqual:@"adjustingExposure"] == NO ||
        [[change objectForKey:NSKeyValueChangeNewKey] boolValue]) {
        return;
    }
    
    adjustingExposure_ = NO;
    
    NSError *error = nil;
    if ([device_ lockForConfiguration:&error]) {
        [device_ setExposureMode:AVCaptureExposureModeLocked];
        [device_ unlockForConfiguration];
    }
    [self performSelector:@selector(autofocus) withObject:nil afterDelay:1];
}

/*!
 * shutter tapped
 */
- (void)handleShutterButtonTapped:(UIButton *)sender{
    [self takePicture];
}

/*!
 * flash mode tapped
 */
- (void)handleFlashModeButtonTapped:(UIButton *)sender{
}

/*!
 * camera device tapped
 */
- (void)handleCameraDeviceButtonTapped:(UIButton *)sender{
    if(device_.position == AVCaptureDevicePositionBack){
        [self initCamera:self.frontFacingCameraDevice];
    }else{
        [self initCamera:self.backCameraDevice];
    }
    [self updateCameraControls];
}

/*!
 * when the device rotated
 */
- (void)deviceOrientationDidChange
{   
    UIDeviceOrientation deviceOrientation = [[UIDevice currentDevice] orientation];
    if (deviceOrientation == UIDeviceOrientationPortrait){
        videoOrientation_ = AVCaptureVideoOrientationPortrait;
    }else if (deviceOrientation == UIDeviceOrientationPortraitUpsideDown){
        videoOrientation_ = AVCaptureVideoOrientationPortraitUpsideDown;
    }else if (deviceOrientation == UIDeviceOrientationLandscapeLeft){        
        videoOrientation_ = AVCaptureVideoOrientationLandscapeRight;
    }else if (deviceOrientation == UIDeviceOrientationLandscapeRight){
        videoOrientation_ = AVCaptureVideoOrientationLandscapeLeft;
    }else{
        return;
    }
    for (AVCaptureConnection* connection in imageOutput_.connections) {
        connection.videoOrientation = videoOrientation_;
    }
    if(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone){
        if(videoOrientation_ != AVCaptureVideoOrientationPortrait &&
           videoOrientation_ != AVCaptureVideoOrientationPortraitUpsideDown){
            return;
        }
    }
    
    viewOrientation_ = deviceOrientation;
    if (previewLayer_) {
        previewLayer_.orientation = [[UIDevice currentDevice] orientation];
        previewLayer_.frame = self.view.bounds;
        scale_ = 1.0;
        croppedViewRect_ = CGRectZero;
    }
}

/*
 * crop image data with data
 * @param data 
 * @param rect crop rect
 */
- (NSData *)cropImageData:(NSData *)data withViewRect:(CGRect)viewRect andScale:(CGFloat)scale{
    if(CGRectEqualToRect(viewRect, CGRectZero)){
        return data;
    }
    
    //read exif data
    CGImageSourceRef cfImage = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    NSDictionary *metadata = (__bridge NSDictionary *)CGImageSourceCopyPropertiesAtIndex(cfImage, 0, nil);
    
    //calculate view -> image scale
    UIImage *image = [UIImage imageWithData:data];
    CGFloat ivScale = 1.0;
    if(image.size.width > image.size.height){
        ivScale = image.size.width / defaultBounds_.size.height;
    }else{
        ivScale = image.size.height / defaultBounds_.size.height;
    }
    //ivScale = scale_ / ivScale;

    //crop image
    CGRect rect = CGRectMake(viewRect.origin.x, viewRect.origin.y, image.size.width / scale, image.size.height / scale);
    rect = [self normalizeCropRect:rect size:image.size];
    
    image = [[image croppedImage:rect] resizedImage:image.size interpolationQuality:kCGInterpolationHigh];
    NSData *croppedData = UIImageJPEGRepresentation(image, 1.0);
    CGImageSourceRef croppedImage = CGImageSourceCreateWithData((__bridge CFDataRef)croppedData, NULL);
    
    //write back exif info
    CGImageSourceRef croppedCFImage = CGImageSourceCreateWithData((__bridge CFDataRef)croppedData, NULL);
    NSMutableDictionary *croppedMetadata = [NSMutableDictionary dictionaryWithDictionary:(__bridge NSDictionary *)CGImageSourceCopyPropertiesAtIndex(croppedCFImage, 0, nil)];
    NSMutableDictionary *exifMetadata = [metadata objectForKey:(NSString *)kCGImagePropertyExifDictionary];
    NSMutableDictionary *tiffMetadata = [croppedMetadata objectForKey:(NSString *)kCGImagePropertyTIFFDictionary];

    [croppedMetadata setValue:[NSNumber numberWithInt:videoOrientation_] forKey:(NSString *)kCGImagePropertyOrientation];
    //[exifMetadata setValue:[NSNumber numberWithInt:videoOrientation_] forKey:(NSString *)kCGImagePropertyOrientation];
    [tiffMetadata setValue:[NSNumber numberWithInt:videoOrientation_] forKey:(NSString *)kCGImagePropertyTIFFOrientation];
    [croppedMetadata setValue:exifMetadata forKey:(NSString *)kCGImagePropertyExifDictionary];
    [croppedMetadata setValue:tiffMetadata forKey:(NSString *)kCGImagePropertyTIFFDictionary];
	CGImageDestinationRef dest = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)croppedData, CGImageSourceGetType(croppedImage), 1, NULL);
	CGImageDestinationAddImageFromSource(dest, croppedImage, 0, (__bridge CFDictionaryRef)croppedMetadata);
	CGImageDestinationFinalize(dest);
    
    NSLog(@"%@", croppedMetadata.description);
    
    //release 
	CFRelease(cfImage);
    CFRelease(croppedCFImage);
    CFRelease(croppedImage);
	CFRelease(dest);
    return croppedData;   
}

/*!
 * normalize crop rect
 * @param rect target rect
 * @return CGRect
 */
- (CGRect)normalizeCropRect:(CGRect)rect size:(CGSize)size{
    CGRect rotatedRect = rect;
    if(videoOrientation_ == AVCaptureVideoOrientationPortrait){
        return rect;
    }else if((viewOrientation_ == UIDeviceOrientationPortrait && 
              videoOrientation_ == AVCaptureVideoOrientationLandscapeLeft) ||
             (viewOrientation_ == UIDeviceOrientationPortraitUpsideDown &&
              videoOrientation_ == AVCaptureVideoOrientationLandscapeRight)){
        rotatedRect.origin.x = size.height - rect.origin.y;
        rotatedRect.origin.y = rect.origin.x;
    }else if((viewOrientation_ == UIDeviceOrientationPortrait && 
              videoOrientation_ == AVCaptureVideoOrientationLandscapeRight) ||
             (viewOrientation_ == UIDeviceOrientationPortraitUpsideDown &&
              videoOrientation_ == AVCaptureVideoOrientationLandscapeLeft)){
        rotatedRect.origin.x = rect.origin.y;
        rotatedRect.origin.y = size.height - rect.origin.x;
    }
    
    if(rotatedRect.origin.x < 0){
        rotatedRect.origin.x = 0;
    }
    if(rotatedRect.origin.y < 0){
        rotatedRect.origin.y = 0;
    }
    if(rotatedRect.origin.x + rotatedRect.size.width > size.width){
        rotatedRect.origin.x = size.width - rotatedRect.size.width;
    }
    if(rotatedRect.origin.y + rotatedRect.size.height > size.height){
        rotatedRect.origin.y = size.height - rotatedRect.size.height;
    }
    return rotatedRect;
}
@end

//-----------------------------------------------------------------------------
//Public Implementations
//-----------------------------------------------------------------------------
@implementation AVFoundationCameraController
@synthesize delegate;
@synthesize showsCameraControls = showsCameraControls_;
@synthesize showsCameraDeviceButton = showsCameraDeviceButton_;
@synthesize showsFlashModeButton = showsFlashModeButton_;
@synthesize showsShutterButton = showsShutterButton_;
@synthesize useTapToFocus = useTapToFocus_;

#pragma mark -
#pragma mark public implementation
/*!
 * initializer
 * @param frame
 */
- (id)initWithFrame:(CGRect)frame{
    self = [super init];
    if(self){
        [self setupInitialState:frame];
    }
    return self;
}


/*!
 * take picture
 */
-(void)takePicture
{
	AVCaptureConnection *videoConnection = nil;
	for (AVCaptureConnection *connection in imageOutput_.connections)
	{
		for (AVCaptureInputPort *port in [connection inputPorts])
		{
			if ([[port mediaType] isEqual:AVMediaTypeVideo] )
			{
				videoConnection = connection;
				break;
			}
		}
		if (videoConnection) { break; }
	}
    
	[imageOutput_ captureStillImageAsynchronouslyFromConnection:videoConnection completionHandler: ^(CMSampleBufferRef imageSampleBuffer, NSError *error)
     {
         NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageSampleBuffer];
         
         UIImage *image = nil;
         if(scale_ != 1.0){
             imageData = [self cropImageData:imageData withViewRect:croppedViewRect_ andScale:scale_];
         }
         
         if([self.delegate respondsToSelector:@selector(cameraController:didFinishPickingImage:)]){
             image = [[UIImage alloc] initWithData:imageData];
             [self.delegate cameraController:self didFinishPickingImage:image];
         }
         
         if([self.delegate respondsToSelector:@selector(cameraController:didFinishPickingImageData:)]){
             [self.delegate cameraController:self didFinishPickingImageData:imageData];
         }
	 }];
}



/*!
 * shows camera controls
 */
- (void)setShowsCameraControls:(BOOL)showsCameraControls{
    showsCameraControls_ = showsCameraControls;
    [self updateCameraControls];
}

/*!
 * shows camera device button
 */
- (void)setShowsCameraDeviceButton:(BOOL)showsCameraDeviceButton{
    showsCameraDeviceButton_ = showsCameraDeviceButton;
    [self updateCameraControls];
}

/*!
 * shows flash mode button
 */
- (void)setShowsFlashModeButton:(BOOL)showsFlashModeButton{
    showsFlashModeButton_ = showsFlashModeButton;
    [self updateCameraControls];
}

/*!
 * shows shutter button
 */
- (void)setShowsShutterButton:(BOOL)showsShutterButton{
    showsShutterButton_ = showsShutterButton;
    [self updateCameraControls];
}

/*!
 * use tap to focus
 */
- (void)setUseTapToFocus:(BOOL)useTapToFocus{
    useTapToFocus_ = useTapToFocus;
    if(useTapToFocus_){
        indicatorLayer_.hidden = NO;
    }else{
        [self autofocus];
        indicatorLayer_.hidden = YES;
    }
}

/*!
 * check the device has multiple video devices
 */
- (BOOL)hasMultipleCameraDevices{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    return devices.count > 1;
}

/*!
 * check the device has front-facing camera device
 */
- (AVCaptureDevice *)frontFacingCameraDevice{
    NSArray *videoDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in videoDevices) {
        if (device.position == AVCaptureDevicePositionFront) {
            return device;
        }
    }
    return nil;
}

/*!
 * check the device has front-facing camera device
 */
- (AVCaptureDevice *)backCameraDevice{
    NSArray *videoDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in videoDevices) {
        if (device.position == AVCaptureDevicePositionBack) {
            return device;
        }
    }
    return nil;
}

/*!
 * check the device has front-facing camera device
 */
- (BOOL)frontFacingCameraAvailable{
    return self.frontFacingCameraDevice != nil;
}

/*!
 * check the device has front-facing camera device
 */
- (BOOL)backCameraAvailable{
    return self.backCameraDevice != nil;
}
@end