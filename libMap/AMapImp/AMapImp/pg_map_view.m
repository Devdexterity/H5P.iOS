/*
 *------------------------------------------------------------------
 *  pandora/feature/map/pg_map_view.mm
 *  Description:
 *      地图视图实现
 *  DCloud Confidential Proprietary
 *  Copyright (c) Department of Research and Development/Beijing/DCloud.
 *  All Rights Reserved.
 *
 *  Changelog:
 *	number	author	modify date  modify record
 *   0       xty     2012-12-10  创建文件
 *   Reviewed @ 20130105 by Lin Xinzheng
 *------------------------------------------------------------------
 */

#import "pg_map.h"
#import "pg_map_view.h"
#import "pg_gis_search.h"
#import "pg_gis_overlay.h"
#import "pg_map_marker.h"
#import "pg_map_overlay.h"
#import "PDRToolSystemEx.h"
#import <MapKit/MapKit.h>
#import "H5CoreJavaScriptText.h"

//缩放控件距离地图边界值
#define PG_MAP_ZOOMCONTROL_GAP 3
//默认经纬度和缩放值
#define PG_MAP_DEFALUT_ZOOM 12
#define PG_MAP_DEFALUT_CENTER_LONGITUDE 116.403865
#define PG_MAP_DEFALUT_CENTER_LATITUDE 39.915136

@implementation PGAMapKey

+(NSString*)verify {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [[AMapServices sharedServices] setEnableHTTPS:YES];
        NSString *amapAppkey = nil;
        NSDictionary *amapInfo = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"amap"];
        if ( [amapInfo isKindOfClass:[NSDictionary class]] ) {
            NSString *tempAK = [amapInfo objectForKey:@"appkey"];
            if ( [tempAK isKindOfClass:[NSString class]] ) {
                amapAppkey = tempAK;
            }
        }
        if ( amapAppkey ) {
            [AMapServices sharedServices].apiKey = amapAppkey;
        }
    });
    return [AMapServices sharedServices].apiKey;
}

@end

static int MapToolFitZoom(int zoom)
{
    if ( zoom < 3 )
        return 3;
    else if( zoom > 19 )
        return 19;
    return zoom;
}

@implementation PGMapZoomControlView

@end

@implementation PGMapView

@synthesize jsBridge;
@synthesize UUID;

-(void)dealloc
{
    self.jsBridge = nil;
    self.delegate = nil;
//    if ( _localService ) {
//        [_localService stopUserLocationService];
//        _localService.delegate = nil;
//        [_localService release];
//    }
    [self removeAllOverlay];
    [_markersDict release];
    [_overlaysDict release];
    [_gisOverlaysDict release];
    [_jsCallbackDict release];
    
    [_zoomControlView release];
    [UUID release];
    [super dealloc];
}

/*
 *------------------------------------------------
 *@summay: 创建一个地图控件
 *@param frame CGRect
 *@return PGMapView*
 *------------------------------------------------
 */
+ (PGMapView*)viewWithFrame:(CGRect)frame params:(NSDictionary*)setInfo
{
    [PGAMapKey verify];
    PGMapView *mapView = [[[PGMapView alloc] initWithFrame:frame params:setInfo] autorelease];
    if ( mapView )
    {
       // mapView.touchPOIEnabled = true;
//        mapView.mapType = MAMapTypeStandard;
//        mapView.showsScale = TRUE;
//        mapView.clipsToBounds = YES;
//        CLLocationCoordinate2D center = {PG_MAP_DEFALUT_CENTER_LATITUDE,PG_MAP_DEFALUT_CENTER_LONGITUDE};
//        [mapView setCenterCoordinate:center animated:YES];
//        mapView.zoomLevel = PG_MAP_DEFALUT_ZOOM;
        return mapView;
    }
    return nil;
}

- (void)close {
   [self removeFromSuperview];
    self.delegate = nil;
}

/*
 *------------------------------------------------
 *@summay: 创建一个地图控件
 *@param frame CGRect
 *@return PGMapView*
 *------------------------------------------------
 */
+ (PGMapView*)viewWithArray:(NSArray*)args
{
    if ( args )
    {
        CGFloat left   = [[args objectAtIndex:0] floatValue];
        CGFloat top    = [[args objectAtIndex:1] floatValue];
        CGFloat width  = [[args objectAtIndex:2] floatValue];
        CGFloat height = [[args objectAtIndex:3] floatValue];
        return [PGMapView viewWithFrame:CGRectMake(left, top, width, height) params:[args objectAtIndex:4]];
    }
    return nil;
}

/*
 *------------------------------------------------
 *@summay: 创建一个地图控件
 *@param frame CGRect
 *@return PGMapView*
 *------------------------------------------------
 */
- (id)initWithFrame:(CGRect)frame params:(NSDictionary*)setInfo;
{
    if ( self = [super initWithFrame:frame] )
    {
        self.delegate = self;
        self.mapType = MAMapTypeStandard;
        self.showsScale = TRUE;
        self.clipsToBounds = YES;
        
        CLLocationCoordinate2D center = {PG_MAP_DEFALUT_CENTER_LATITUDE,PG_MAP_DEFALUT_CENTER_LONGITUDE};
        [self setCenterCoordinate:center animated:YES];
        
        PGMapCoordinate *centerCoordinate = [PGMapCoordinate pointWithJSON:[setInfo objectForKey:@"center"]];
        if ( centerCoordinate ) {
            [self setCenterCoordinate:[centerCoordinate point2CLCoordinate]
                                    animated:YES];
        }
        self.zoomLevel = MapToolFitZoom([[setInfo objectForKey:@"zoom"] intValue]);
        self.showTraffic = [[setInfo objectForKey:@"traffic"] boolValue];
        BOOL zoomControls = [[setInfo objectForKey:@"zoomControls"] boolValue];
        if ( zoomControls ) {
            [self showZoomControl];
        }
        [self setMapTypeJS:[NSArray arrayWithObject:[setInfo objectForKey:@"type"]]];
        self.positionType = PGMapViewPositionStatic;
        NSString *position = [setInfo objectForKey:@"position"];
        if ( [position isKindOfClass:[NSString class]]
            && NSOrderedSame == [@"absolute" caseInsensitiveCompare:position]) {
            self.positionType = PGMapViewPositionAbsolute;
        }
        
//        UITapGestureRecognizer *taprecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapCallback:)];
//        taprecognizer.numberOfTouchesRequired = 1; 
//        taprecognizer.numberOfTapsRequired = 1;
//        taprecognizer.cancelsTouchesInView = NO;
//       // taprecognizer.delaysTouchesBegan = YES;
//       // taprecognizer.delaysTouchesEnded = YES;
//        [self addGestureRecognizer:taprecognizer];
//        [taprecognizer release];
        return self;
    }
    return nil;
}

/*
 *------------------------------------------------
 *@summay: 地图点击事件回调
 *@param sender UITapGestureRecognizer*
 *@return 
 *@remark
 *    该函数没有排除覆盖物区域
 *------------------------------------------------
 */

-(void)tapCallback:(UITapGestureRecognizer*)sender
{
    CGPoint point = [sender locationInView:self];
    
    //排除缩放控件区域
    if ( _zoomControlView
        && CGRectContainsPoint(_zoomControlView.frame, point))
        return;
    
    //排除覆盖物区域

    CLLocationCoordinate2D coordiante = [self convertPoint:point toCoordinateFromView:self];
    NSString *jsObjectF =
    @"{\
        var plus = %@; \
        var args = new plus.maps.Point(%f,%f);\
        plus.maps.__bridge__.execCallback('%@', args);\
      }";
    NSString *javaScript = [NSString stringWithFormat:jsObjectF, [H5CoreJavaScriptText plusObject], coordiante.longitude, coordiante.latitude, self.UUID];
    [jsBridge asyncWriteJavascript:javaScript];
}

/*
 *------------------------------------------------
 *@summay: 调整地图缩放控件
 *@param 
 *@return
 *@remark
 *    
 *------------------------------------------------
 */
- (void)resizeZoomControl
{
    if ( _zoomControlView )
    {
        CGRect mapRect = self.bounds;
        CGSize zoomControlSize = _zoomControlView.bounds.size;
        CGPoint center;
        center.x = mapRect.size.width - zoomControlSize.width/2 - PG_MAP_ZOOMCONTROL_GAP;
        center.y = mapRect.size.height - zoomControlSize.height/2 - PG_MAP_ZOOMCONTROL_GAP;
        _zoomControlView.center = center;
    }
}

/*
 *------------------------------------------------
 *@summay: 显示地图缩放控件
 *@param
 *@return
 *@remark
 *------------------------------------------------
 */
- (void)showZoomControl
{
    if ( !_zoomControlView )
    {
        PGMapZoomControlView *zoomControlView = [[PGMapZoomControlView alloc] init];
        zoomControlView.alpha = 0.5f;
        zoomControlView.minimumValue= 3;
        zoomControlView.maximumValue= 19;
        zoomControlView.stepValue= 1;
        zoomControlView.value= self.zoomLevel;
        zoomControlView.center= self.center;
        [zoomControlView addTarget:self action:@selector(zoomControlCallback:) forControlEvents:UIControlEventValueChanged];
        _zoomControlView = zoomControlView;
        [self resizeZoomControl];
        [self addSubview:_zoomControlView];
    }
    if ( _zoomControlView.hidden )
    { _zoomControlView.hidden = NO; }
}

/*
 *------------------------------------------------
 *@summay: 隐藏地图缩放控件
 *@param
 *@return
 *@remark
 *------------------------------------------------
 */
- (void)hideZoomControl
{
    if ( _zoomControlView && !_zoomControlView.hidden)
    { _zoomControlView.hidden = YES; }
}

/*
 *------------------------------------------------
 *@summay: 地图缩放控件事件处理
 *@param sender PGMapZoomControlView*
 *@return
 *@remark
 *------------------------------------------------
 */
-(void)zoomControlCallback:(PGMapZoomControlView*)sender
{/*
    CGFloat value = _zoomControlView.value;
    CGFloat currentZoom = self.zoomLevel;
    if ( value >= currentZoom ) {
        [self zoomIn];
    } else {
        [self zoomOut];
    }*/
    self.zoomLevel = _zoomControlView.value; //MapToolFitZoom(_zoomControlView.value);
}

#pragma mark invoke js method
#pragma mark -----------------------------
/*
 *------------------------------------------------
 *@summay: 设置是否显示地图
 *@param sender js pass
 *@return
 *@remark
 *------------------------------------------------
 */
- (void)showJS:(NSArray*)args
{
    NSNumber *value = [args objectAtIndex:0];
    if ( value && [value isKindOfClass:[NSNumber class]] )
    {
        self.hidden = NO;
        if ( !self.hidden )
        {
            CGFloat left   = [[args objectAtIndex:0] floatValue];
            CGFloat top    = [[args objectAtIndex:1] floatValue];
            CGFloat width  = [[args objectAtIndex:2] floatValue];
            CGFloat height = [[args objectAtIndex:3] floatValue];
            self.frame = CGRectMake(left, top, width, height);
            [self resizeZoomControl];
        }
    }
}

/*
 *------------------------------------------------
 *@summay: 设置是否显示地图
 *@param sender js pass
 *@return
 *@remark
 *------------------------------------------------
*/
- (void)hideJS:(NSArray*)args
{
  //  NSNumber *value = [args objectAtIndex:0];
   // if ( value && [value isKindOfClass:[NSNumber class]] )
    {
        self.hidden = YES;
    }
}

/*
 *------------------------------------------------
 *@summay: 调整地图的大小
 *@param sender js pass
 *@return
 *@remark
 *------------------------------------------------
 */
- (void)resizeJS:(NSArray*)args
{
    if ( args && [args isKindOfClass:[NSArray class]] )
    {
        CGFloat left   = [[args objectAtIndex:0] floatValue];
        CGFloat top    = [[args objectAtIndex:1] floatValue];
        CGFloat width  = [[args objectAtIndex:2] floatValue];
        CGFloat height = [[args objectAtIndex:3] floatValue];
        self.frame = CGRectMake(left, top, width, height);
        [self resizeZoomControl];
    }
}

/*
 *------------------------------------------------
 *@summay: 设置地图中心缩放级别
 *@param sender js pass
 *@return
 *@remark
 *------------------------------------------------
 */
- (void)setZoomJS:(NSArray*)args
{
    if ( args && [args isKindOfClass:[NSArray class]] )
    {
        NSNumber *innerZoom = [args objectAtIndex:0];
        if ( innerZoom && [innerZoom isKindOfClass:[NSNumber class]])
        {
            int nZoom = MapToolFitZoom([innerZoom intValue]);
            self.zoomLevel = nZoom;
            if ( _zoomControlView )
            { _zoomControlView.value = self.zoomLevel; }
        }
    }
}

/*
 *------------------------------------------------
 *@summay: 设置地图中心缩放级别
 *@param sender js pass
 *@return
 *@remark
 *------------------------------------------------
 */
- (void)setMapTypeJS:(NSArray*)args
{
    if ( args && [args isKindOfClass:[NSArray class]] )
    {
        NSString *mapType = [args objectAtIndex:0];
        if ( [mapType isKindOfClass:[NSString class]]  )
        {
            if ( [mapType isEqualToString:@"MAPTYPE_SATELLITE"] )
            {
                if ( MAMapTypeSatellite!= self.mapType )
                    self.mapType = MAMapTypeSatellite;
            }
            else if( [mapType isEqualToString:@"MAPTYPE_NORMAL"] )
            {
                if ( MAMapTypeStandard!= self.mapType )
                    self.mapType = MAMapTypeStandard;
            }
        }
    }
}

/*
 *------------------------------------------------
 *@summay: 设置地图中心区域
 *@param sender js pass
 *@return
 *@remark
 *------------------------------------------------
 */
- (void)setCenterJS:(NSArray*)args
{
    if ( args && [args isKindOfClass:[NSArray class]] )
    {
        PGMapCoordinate *center = [PGMapCoordinate pointWithJSON:[args objectAtIndex:0]];
        if ( center )
        {
            [self setCenterCoordinate:[center point2CLCoordinate] animated:YES];
        }
    }
}

/*
 *------------------------------------------------
 *@summay: 设置地图显示区域
 *@param sender js pass
 *@return
 *@remark
 *------------------------------------------------
 */
- (void)centerAndZoomJS:(NSArray*)args
{
    if ( args && [args isKindOfClass:[NSArray class]] )
    {
        PGMapCoordinate *center = [PGMapCoordinate pointWithJSON:[args objectAtIndex:0]];
        NSNumber *innerZoom = [args objectAtIndex:1];
        if ( center
            && innerZoom
            && [innerZoom isKindOfClass:[NSNumber class]])
        {
            int nZoom = MapToolFitZoom([innerZoom intValue]);
            self.zoomLevel = nZoom;
            if ( _zoomControlView )
            { _zoomControlView.value = self.zoomLevel; }
            [self setCenterCoordinate:[center point2CLCoordinate] animated:YES];
        }
    }
}

/*
 *------------------------------------------------
 *@summay: 设置是否显示用户位置蓝点
 *@param sender js pass
 *@return
 *@remark
 *------------------------------------------------
 */
- (void)showUserLocationJS:(NSArray*)args
{
    if ( args && [args isKindOfClass:[NSArray class]] )
    {
        NSNumber *visable = [args objectAtIndex:0];
//        if ( nil == _localService ) {
//            _localService = [[BMKLocationService alloc] init];
//            _localService.delegate = self;
//            [_localService startUserLocationService];
//        }
        self.showsUserLocation = [visable boolValue];
      //  self.userLocation.title = nil;
    }
}

/*
 *------------------------------------------------
 *@summay: 设置是否显示交通图
 *@param sender js pass
 *@return
 *@remark
 *------------------------------------------------
 */
- (void)setTrafficJS:(NSArray*)args
{
    if ( args && [args isKindOfClass:[NSArray class]] )
    {
        NSNumber *value = [args objectAtIndex:0];
        if ( value && [value isKindOfClass:[NSNumber class]] )
        {
            if ( [value boolValue] )
            { self.showTraffic = true; }
            else { self.showTraffic = false; }
        }
    }
}

/*
 *------------------------------------------------
 *@summay: 设置是否显示缩放控件
 *@param sender js pass
 *@return
 *@remark
 *------------------------------------------------
 */
- (void)showZoomControlsJS:(NSArray*)args
{
    NSNumber *value = [args objectAtIndex:0];
    if ( value && [value isKindOfClass:[NSNumber class]] )
    {
        if ( [value boolValue] )
        {
            [self showZoomControl];
        }
        else
        {
            [self hideZoomControl];
        }
    }
}
/*
 *------------------------------------------------
 *@summay: 添加覆盖物
 *@param sender js pass
 *@return
 *@remark
 *     重置地图只恢复经纬度和zoomlevel
 *------------------------------------------------
 */
- (void)addOverlayJS:(NSArray*)args
{
    if ( args && [args isKindOfClass:[NSArray class]] )
    {
        NSString *overlayUUID = [args objectAtIndex:0];
        if ( overlayUUID && [overlayUUID isKindOfClass:[NSString class]] )
        {
            NSObject *overlay = [self.jsBridge.nativeOjbectDict objectForKey:overlayUUID];
            if ( [overlay isKindOfClass:[PGMapMarker class]] )
            {
                [self addMarker:(PGMapMarker*)overlay];
            }
            else if( [overlay isKindOfClass:[PGMapOverlay class]] )
            {
                [self addMapOverlay:(PGMapOverlay*)overlay];
            }
            else if( [overlay isKindOfClass:[PGGISOverlay class]] )
            {
                [self addGISOverlay:(PGGISOverlay*)overlay];
            }
        }
    }
}

/*
 *------------------------------------------------
 *@summay: 移走地图覆盖物
 *@param sender js pass
 *@return
 *@remark
 *------------------------------------------------
 */
- (void)removeOverlayJS:(NSArray*)args
{
    if ( args && [args isKindOfClass:[NSArray class]] )
    {
        NSString *overlayUUID = [args objectAtIndex:0];
        if ( overlayUUID && [overlayUUID isKindOfClass:[NSString class]] )
        {
            NSObject *overlay = [self.jsBridge.nativeOjbectDict objectForKey:overlayUUID];
            if ( [overlay isKindOfClass:[PGMapMarker class]] )
            {
                [self removeMarker:(PGMapMarker*)overlay];
            }
            else if( [overlay isKindOfClass:[PGMapOverlay class]] )
            {
                [self removeMapOverlay:(PGMapOverlay*)overlay];
            }
            else if( [overlay isKindOfClass:[PGGISOverlay class]] )
            {
                [self removeGISOverlay:(PGGISOverlay*)overlay];
            }
        }
    }
}

/*
 *------------------------------------------------
 *@summay: 移走所有的覆盖
 *@param sender js pass
 *@return
 *@remark
 *------------------------------------------------
 */
- (void)clearOverlaysJS:(NSArray*)args
{
    [self removeAllOverlay];
}

/*
 *------------------------------------------------
 *@summay: 重置地图
 *@param sender js pass
 *@return
 *@remark
 *     重置地图只恢复经纬度和zoomlevel
 *------------------------------------------------
 */
- (void)resetJS:(NSArray*)args
{
    CLLocationCoordinate2D center = {PG_MAP_DEFALUT_CENTER_LATITUDE,PG_MAP_DEFALUT_CENTER_LONGITUDE};
    self.zoomLevel = PG_MAP_DEFALUT_ZOOM;
    if ( _zoomControlView )
    { _zoomControlView.value = self.zoomLevel; }
    [self setCenterCoordinate:center animated:NO];
   // self.rotationDegree = 0;
}

/*
 *------------------------------------------------
 *@summay: 获取当前中心点的经纬度
 *@param sender js pass
 *@return
 *@remark
 *     该接口和getCenterCoordinate的区别为该接口会通知js
 *------------------------------------------------
 */
- (void)getCurrentCenterJS:(NSArray*)args
{
    if ( args && [args isKindOfClass:[NSArray class]] )
    {
        NSString *uuid = [args objectAtIndex:0];
        CLLocationCoordinate2D coordinate = self.centerCoordinate;
        NSString *jsObjectF =
        @"{\
        var plus = %@;\
        var point = new plus.maps.Point(%f,%f);\
        var args = {'state':0, 'point':point};\
        plus.maps.__bridge__.execCallback('%@', args);}";
        NSMutableString *javascript = [NSMutableString stringWithFormat:jsObjectF, [H5CoreJavaScriptText plusObject],coordinate.longitude, coordinate.latitude, uuid];
        [self.jsBridge asyncWriteJavascript:javascript];
    }
}

/*
 *------------------------------------------------
 *@summay: 获取用户当前的位置
 *@param sender js pass
 *@return
 *@remark
 *   该接口会通知js
 *------------------------------------------------
 */
- (void)getUserLocationJS:(NSArray*)args
{
    if ( args && [args isKindOfClass:[NSArray class]] )
    {
        NSString *uuid = [args objectAtIndex:0];
        
        if ( NO == self.showsUserLocation ) {
            self.showsUserLocation = true;
        }
//
        MAUserLocation *userLocation = self.userLocation;
        if ( userLocation.location )
        {
            CLLocation *location = userLocation.location;
            CLLocationCoordinate2D coordinate = location.coordinate;
            NSString *jsObjectF =
            @"{ var plus = %@;\
            var point = new plus.maps.Point(%f,%f);\
            var args = {'state':0, 'point':point};\
            plus.maps.__bridge__.execCallback('%@', args);}";
            NSMutableString *javascript = [NSMutableString stringWithFormat:jsObjectF, [H5CoreJavaScriptText plusObject], coordinate.longitude, coordinate.latitude, uuid];
            [self.jsBridge asyncWriteJavascript:javascript];
        }
        else
        {
            if ( !_jsCallbackDict )
                _jsCallbackDict = [[NSMutableArray alloc] initWithCapacity:10];
            [_jsCallbackDict addObject:uuid];
        }
    }
}
- (NSData*)getBoundsJS:(NSArray*)args {
    CLLocationCoordinate2D tl = [self convertPoint:CGPointMake(self.bounds.size.width, 0) toCoordinateFromView:self];
    CLLocationCoordinate2D rb = [self convertPoint:CGPointMake(0, self.bounds.size.height) toCoordinateFromView:self];
    PGMapBounds *bounds = [PGMapBounds boundsWithNorthEase:tl southWest:rb];
    
    return [jsBridge resultWithJSON:[bounds toJSON]];
}
#pragma mark Map tools
#pragma mark -----------------------------
/*
 *------------------------------------------------
 *@summay: 该接口用来添加gis search中获取到的路径
 *@param 
 *       overlay js pass
 *@return
 *@remark
 *------------------------------------------------
 */
- (void)addGISOverlay:(PGGISOverlay*)overlay
{
    if ( !overlay )
        return;
    if ( overlay.belongMapview )
        return;
    
    if ( !_gisOverlaysDict )
        _gisOverlaysDict = [[NSMutableArray alloc] initWithCapacity:10];
    overlay.belongMapview = self;
   // [_overlaysDict setObject:overlay forKey:overlay.UUID ];
    [_gisOverlaysDict addObject:overlay];
    [self addAnnotations:overlay.markers];
    [self addOverlay:overlay.polyline];
}

/*
 *------------------------------------------------
 *@summay: 该接口用来 移除gis search中获取到的路径
 *@param
 *       overlay js pass
 *@return
 *@remark
 *------------------------------------------------
 */
- (void)removeGISOverlay:(PGGISOverlay*)overlay
{
    if ( !overlay )
        return;
    if ( !overlay.belongMapview )
        return;
    
    overlay.belongMapview = nil;
    [_gisOverlaysDict removeObject:overlay];
    // [_overlaysDict setObject:overlay forKey:overlay.UUID ];
    [self removeAnnotations:overlay.markers];
    [self removeOverlay:overlay.polyline];
}

/*
 *------------------------------------------------
 *@summay: 该接口用来添加标记
 *@param
 *       marker js pass
 *@return
 *@remark
 *------------------------------------------------
 */
- (void)addMarker:(PGMapMarker*)marker
{
    if ( !marker )
        return;
    //添加过不在添加
    if ( marker.belongMapview )
        return;
    
    if ( !_markersDict )
        _markersDict = [[NSMutableArray alloc] initWithCapacity:10];
    marker.belongMapview = self;
    [_markersDict addObject:marker];
    [self addAnnotation:(id<MAAnnotation>)marker];
}

/*
 *------------------------------------------------
 *@summay: 移走一个标记
 *@param
 *       marker js pass
 *@return
 *@remark
 *------------------------------------------------
 */
- (void)removeMarker:(PGMapMarker*)marker
{
    if ( !marker )
        return;
    if ( !marker.belongMapview )
        return;
    
    marker.belongMapview = nil;
    [_markersDict removeObject:marker];
    [self removeAnnotation:(id<MAAnnotation>)marker];
}

/*
 *------------------------------------------------
 *@summay: 移走一个标记
 *@param
 *       marker js pass
 *@return
 *@remark
 *
 *------------------------------------------------
 */
- (void)addMapOverlay:(PGMapOverlay*)overlay;
{
    if ( !overlay )
        return;
    if ( !overlay.overlay/* || !overlay.overlayView*/ )
        return;
    //添加过不在添加
    if ( overlay.belongMapview )
        return;
    
    if ( !_overlaysDict )
        _overlaysDict = [[NSMutableArray alloc] initWithCapacity:10];
    overlay.belongMapview = self;
    [_overlaysDict addObject:overlay];
    if ( !overlay.hidden ) {
        [self addOverlay:overlay.overlay];
    }
}

- (void)setMapOverlay:(PGMapOverlay*)overlay isVisable:(BOOL)visable {
    if ( visable ) {
        [self addOverlay:overlay.overlay];
    } else {
        [self removeOverlay:overlay.overlay];
    }
}

/*
 *------------------------------------------------
 *@summay: 移走一个标记
 *@param
 *       marker js pass
 *@return
 *@remark
 *
 *------------------------------------------------
 */
- (void)removeMapOverlay:(PGMapOverlay*)overlay
{
    if ( !overlay || !overlay.overlay  )
        return;
    if ( !overlay.belongMapview )
        return;
    [self removeOverlay:overlay.overlay];
    [_overlaysDict removeObject:overlay];
    overlay.belongMapview = nil;
}

/*------------------------------------------------
 *@summay: 移走所有的标记
 *@param
 *       marker js pass
 *@return
 *@remark
 *
 *------------------------------------------------
 */
- (void)removeAllOverlay;
{
    for (PGMapMarker *marker in _markersDict )
    {
        [self removeAnnotation:marker];
    }
    
    for ( PGMapOverlay *pdlOvlery in _overlaysDict)
    {
        if ( pdlOvlery && pdlOvlery.overlay  )
        {
            pdlOvlery.belongMapview = nil;
            [self removeOverlay:pdlOvlery.overlay];
        }
    }
    
    for ( PGGISOverlay *gisOverlay in _gisOverlaysDict )
    {
        gisOverlay.belongMapview = nil;
        [self removeAnnotations:gisOverlay.markers];
        [self removeOverlay:gisOverlay.polyline];
    }
    
    [_markersDict removeAllObjects];
    [_overlaysDict removeAllObjects];
    [_gisOverlaysDict removeAllObjects];
}

/*
- (NSString*)getPDLBundle:(NSString *)filename
{
#define MYBUNDLE_NAME @ "pdlmap.bundle"
#define MYBUNDLE_PATH [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: MYBUNDLE_NAME]
#define MYBUNDLE [NSBundle bundleWithPath: MYBUNDLE_PATH]
	NSBundle * libBundle = MYBUNDLE ;
	if ( libBundle && filename )
    {
		NSString * s=[[libBundle resourcePath ] stringByAppendingPathComponent : filename];
		return s;
	}
	return nil ;
}
*/

/*------------------------------------------------
 *@summay: 生成gis 路线中标记点展现视图
 *@param
 *       mapview 地图实例
 *       routeAnnotation
 *@return
 *       MAAnnotationView*
 *@remark
 *
 *------------------------------------------------
 */
#pragma mark Map tools
#pragma mark -----------------------------
//- (void)mapView:(BMKMapView *)mapView onClickedMapBlank:(CLLocationCoordinate2D)coordinate {
//    NSString *jsObjectF =
//    @"var args = new plus.maps.Point(%f,%f);\
//    window.plus.maps.__bridge__.execCallback('%@', args);";
//    NSString *javaScript = [NSString stringWithFormat:jsObjectF, coordinate.longitude, coordinate.latitude, self.UUID];
//    [jsBridge asyncWriteJavascript:javaScript];
//}

- (MAAnnotationView*)getRouteAnnotationView:(MAMapView *)mapview viewForAnnotation:(PGGISMarker*)routeAnnotation
{
	MAAnnotationView* view = nil;
	switch (routeAnnotation.type) {
		case 0:
		{
			view = [mapview dequeueReusableAnnotationViewWithIdentifier:@"start_node"];
			if (view == nil) {
				view = [[[MAAnnotationView alloc]initWithAnnotation:routeAnnotation reuseIdentifier:@"start_node"] autorelease];
				view.image = [UIImage imageNamed:@"AMap.bundle/images/icon_nav_start"];
				view.centerOffset = CGPointMake(0, -(view.frame.size.height * 0.5));
				view.canShowCallout = TRUE;
			}
			view.annotation = routeAnnotation;
		}
			break;
		case 1:
		{
			view = [mapview dequeueReusableAnnotationViewWithIdentifier:@"end_node"];
			if (view == nil) {
				view = [[[MAAnnotationView alloc]initWithAnnotation:routeAnnotation reuseIdentifier:@"end_node"] autorelease];
				view.image = [UIImage imageNamed:@"AMap.bundle/images/icon_nav_end"];
				view.centerOffset = CGPointMake(0, -(view.frame.size.height * 0.5));
				view.canShowCallout = TRUE;
			}
			view.annotation = routeAnnotation;
		}
			break;
		case 2:
		{
			view = [mapview dequeueReusableAnnotationViewWithIdentifier:@"bus_node"];
			if (view == nil) {
				view = [[[MAAnnotationView alloc]initWithAnnotation:routeAnnotation reuseIdentifier:@"bus_node"] autorelease];
				view.image = [UIImage imageNamed:@"AMap.bundle/images/icon_nav_bus"];
				view.canShowCallout = TRUE;
			}
			view.annotation = routeAnnotation;
		}
			break;
		case 3:
		{
			view = [mapview dequeueReusableAnnotationViewWithIdentifier:@"rail_node"];
			if (view == nil) {
				view = [[[MAAnnotationView alloc]initWithAnnotation:routeAnnotation reuseIdentifier:@"rail_node"] autorelease];
				view.image = [UIImage imageNamed:@"AMap.bundle/images/icon_nav_rail"];
				view.canShowCallout = TRUE;
			}
			view.annotation = routeAnnotation;
		}
			break;
		case 4:
		{
			view = [mapview dequeueReusableAnnotationViewWithIdentifier:@"route_node"];
			if (view == nil) {
				view = [[[MAAnnotationView alloc]initWithAnnotation:routeAnnotation reuseIdentifier:@"route_node"]autorelease];
				view.canShowCallout = TRUE;
			} else {
				[view setNeedsDisplay];
			}
			
			UIImage* image = [UIImage imageNamed:@"AMap.bundle/images/icon_direction"];
			view.image = [image imageRotatedByDegrees:routeAnnotation.degree supportRetina:YES scale:1.0f];
			view.annotation = routeAnnotation;
			
		}
			break;
		default:
			break;
	}
	
	return view;
}

/*
 *------------------------------------------------
 *根据anntation生成对应的View
 *@param mapView 地图View
 *@param annotation 指定的标注
 *@return 生成的标注View
 *------------------------------------------------
 */
- (MAAnnotationView *)mapView:(MAMapView *)mapView viewForAnnotation:(id <MAAnnotation>)annotation
{
    if ( [annotation isKindOfClass:[PGGISMarker class]] )
    {
        PGGISMarker *marker = (PGGISMarker*)annotation;
        MAAnnotationView *view = [self getRouteAnnotationView:mapView viewForAnnotation:annotation];
        view.hidden = marker.hidden;
        return view;
    }
    else if ( [annotation isMemberOfClass:[PGMapMarker class]] )
    {
        PGMapMarker *marker = (PGMapMarker*)annotation;
        NSString *reusableIdentifier = @"io_dcloud_map_markerView";
        PGMapMarkerView *pinAnnView = (PGMapMarkerView*)[mapView dequeueReusableAnnotationViewWithIdentifier:reusableIdentifier];
        if ( nil == pinAnnView ) {
            pinAnnView = [[[PGMapMarkerView alloc]initWithAnnotation:marker reuseIdentifier:reusableIdentifier] autorelease];
            pinAnnView.annotation = annotation;
        } else {
            pinAnnView.annotation = annotation;
        }
        pinAnnView.canShowCallout = NO;
        pinAnnView.draggable = marker.canDraggable;
        [pinAnnView setDragState:MAAnnotationViewDragStateNone];
        pinAnnView.hidden = marker.hidden;
      //  pinAnnView.selected = marker.bubblePop;
        //[pinAnnView setSelected:YES];
        //pinAnnView.enabled = !marker.hidden;
        [pinAnnView reload];
        if ( marker.selected ) {
            dispatch_async(dispatch_get_main_queue(), ^(void) {
                [mapView selectAnnotation:marker animated:NO];
            });
        }
        return pinAnnView;
    }
    return nil;
}

/*
 *------------------------------------------------
 *根据overlay生成对应的View
 *@param mapView 地图View
 *@param overlay 指定的overlay
 *@return 生成的覆盖物View
 *------------------------------------------------
 */
- (MAOverlayView *)mapView:(MAMapView *)mapView viewForOverlay:(id <MAOverlay>)overlay
{
    //if ( [overlay isKindOfClass:[PGMapOverlay class]] )
    {
        for ( PGMapOverlay *pdlOverlay in _overlaysDict)
        {
            if ( pdlOverlay.overlay == overlay ){
                //return pdlOverlay.overlayView;
                MAOverlayPathView *pathView = nil;
                if ( [pdlOverlay isKindOfClass:[PGMapCircle class]] ) {
                    pathView = [[[MACircleView alloc]initWithCircle:overlay] autorelease];
                } else if ( [pdlOverlay isKindOfClass:[PGMapPolyline class]]){
                    pathView = [[[MAPolylineView alloc] initWithPolyline:overlay] autorelease];
                } else if ( [pdlOverlay isKindOfClass:[PGMapPolygon class]]){
                    pathView = [[[MAPolygonView alloc] initWithPolygon:overlay] autorelease];
                }
                pathView.fillColor = pdlOverlay.fillColor;
                pathView.strokeColor = pdlOverlay.strokeColor;
                pathView.lineWidth = pdlOverlay.lineWidth;
                return pathView;
            }
        }
    }
    
    
    
    if ([overlay isKindOfClass:[MAPolyline class]])
    {
        MAPolylineView* polylineView = [[[MAPolylineView alloc] initWithPolyline:overlay] autorelease];
        polylineView.fillColor = [[UIColor blueColor] colorWithAlphaComponent:1];
        polylineView.strokeColor = [[UIColor blueColor] colorWithAlphaComponent:1];
        polylineView.lineWidth = 4.0;
        return polylineView;
    }
    return nil;
}

/*
 *------------------------------------------------
 *当选中一个annotation views时，调用此接口
 *@param mapView 地图View
 *@param views 选中的annotation views
 *------------------------------------------------
 */
- (void)mapView:(MAMapView *)mapView didSelectAnnotationView:(MAAnnotationView *)view
{
    id<MAAnnotation> annotation = view.annotation;
    if ( annotation && [annotation isKindOfClass:[PGMapMarker class]] )
    {
        PGMapMarker *marker = (PGMapMarker*)annotation;
        marker.selected = YES;
//        NSString * jsObjectF = @"var args = {type:'markerclick'};\
//        window.plus.maps.__bridge__.execCallback('%@', args);";
//        NSString *javaScript = [NSString stringWithFormat:jsObjectF, marker.UUID];
//        [jsBridge asyncWriteJavascript:javaScript];
    }
}

- (void)mapView:(MAMapView *)mapView didDeselectAnnotationView:(MAAnnotationView *)view
{
    id<MAAnnotation> annotation = view.annotation;
    if ( annotation && [annotation isKindOfClass:[PGMapMarker class]] )
    {
        PGMapMarker *marker = (PGMapMarker*)annotation;
        marker.selected = NO;
       // [markerView showBubble:NO animated:NO];
    }
}

/*
 *------------------------------------------------
 *用户位置更新后，会调用此函数
 *@param mapView 地图View
 *@param userLocation 新的用户位置
 *------------------------------------------------
 */
- (void)mapView:(MAMapView *)mapView didUpdateUserLocation:(MAUserLocation *)userLocation updatingLocation:(BOOL)updatingLocation
{
    if ( userLocation && userLocation.location && [_jsCallbackDict count])
    {
        CLLocation *location = userLocation.location;
        CLLocationCoordinate2D coordinate = location.coordinate;
        
        NSArray *callbackDict = [NSArray arrayWithArray:_jsCallbackDict];
        [_jsCallbackDict removeAllObjects];
        for ( NSString *aUUID in callbackDict )
        {
            NSString *jsObjectF =
            @"{ var plus = %@;\
            var point = new plus.maps.Point(%f,%f);\
            var args = {'state':0, 'point':point};\
            plus.maps.__bridge__.execCallback('%@', args);}";
            NSMutableString *javascript = [NSMutableString stringWithFormat:jsObjectF, [H5CoreJavaScriptText plusObject],coordinate.longitude, coordinate.latitude, aUUID];
            [self.jsBridge asyncWriteJavascript:javascript];
        }
    }
}
/*
 *------------------------------------------------
 *定位失败后，会调用此函数
 *@param mapView 地图View
 *@param error 错误号，参考CLError.h中定义的错误号
 *------------------------------------------------
 */
- (void)mapView:(MAMapView *)mapView didFailToLocateUserWithError:(NSError *)error;
{
    if ( [_jsCallbackDict count] )
    {
        NSArray *callbackDict = [NSArray arrayWithArray:_jsCallbackDict];
        [_jsCallbackDict removeAllObjects];
        for ( NSString *aUUID in callbackDict )
        {
            NSString *jsObjectF =
            @"{ var plus = %@;\
            var point = new plus.maps.Point(%f,%f);\
            var args = {'state':-1, 'point':point};\
            plus.maps.__bridge__.execCallback('%@', args);}";
            NSMutableString *javascript = [NSMutableString stringWithFormat:jsObjectF, [H5CoreJavaScriptText plusObject], 0.0f, 0.0f, aUUID];
            [self.jsBridge asyncWriteJavascript:javascript];
        }
    }
}

/*
 *------------------------------------------------
 *地图区域改变完成后会调用此接口
 *@param mapview 地图View
 *@param animated 是否动画
 *------------------------------------------------
 */
- (void)mapView:(MAMapView *)mapView regionDidChangeAnimated:(BOOL)animated
{
    if ( _zoomControlView ){
        _zoomControlView.value = self.zoomLevel;
    }
    CLLocationCoordinate2D tl = [self convertPoint:CGPointMake(self.bounds.size.width, 0) toCoordinateFromView:self];
    CLLocationCoordinate2D rb = [self convertPoint:CGPointMake(0, self.bounds.size.height) toCoordinateFromView:self];
    
    NSString *jsObjectF =
    @"window.setTimeout(function(){ %@.maps.__bridge__.execCallback('%@', {callbackType:'change',zoom:%f,center:{long:%f,lat:%f},northease:{long:%f,lat:%f},southwest:{long:%f,lat:%f}});},0)";
    NSString *javaScript = [NSString stringWithFormat:jsObjectF,
                            [H5CoreJavaScriptText plusObject],
                            self.UUID,
                            self.zoomLevel,
                            self.centerCoordinate.longitude, self.centerCoordinate.latitude,
                            tl.longitude, tl.latitude, rb.longitude, rb.latitude];
    [jsBridge asyncWriteJavascript:javaScript];
}

#pragma mark static method
#pragma mark -----------------------------
/*
 *------------------------------------------------
 *invake js openSysMap
 *@param command PDLMethod*
 *@return 无
 *------------------------------------------------
 */
+ (void)openSysMap:(NSArray*)command
{
    NSMutableDictionary *dstDict = [command objectAtIndex:0];
    NSString *dstAddr = [PGPluginParamHelper getStringValue:[command objectAtIndex:1]];
    NSMutableDictionary *srcDict = [command objectAtIndex:2];
    
    if ( srcDict && [srcDict isKindOfClass:[NSMutableDictionary class]]
        && dstDict && [dstDict isKindOfClass:[NSMutableDictionary class]])
    {
        PGMapCoordinate *srcPoi = [PGMapCoordinate pointWithJSON:srcDict];
        PGMapCoordinate *dstPoi = [PGMapCoordinate pointWithJSON:dstDict];
        if ( srcPoi && dstPoi ) {
            if ( [PTDeviceOSInfo systemVersion] > PTSystemVersion7Series ) {
                NSString *mapURL = [NSString stringWithFormat:@"http://maps.apple.com/?saddr=%f,%f&daddr=%f,%f",
                                    srcPoi.latitude, srcPoi.longitude,
                                    dstPoi.latitude, dstPoi.longitude ];
                [[UIApplication sharedApplication] openURL:[NSURL URLWithString:mapURL]];
            } else if ([PTDeviceOSInfo systemVersion] > PTSystemVersion5Series){
                MKPlacemark *srcPlaceMark = [[[MKPlacemark alloc] initWithCoordinate:[srcPoi point2CLCoordinate] addressDictionary:nil] autorelease];
                MKPlacemark *dstPlaceMark = [[[MKPlacemark alloc] initWithCoordinate:[dstPoi point2CLCoordinate] addressDictionary:dstAddr?@{@"Name":dstAddr}:nil] autorelease];
                MKMapItem *srcLocation = [[[MKMapItem alloc] initWithPlacemark:srcPlaceMark] autorelease];
                MKMapItem *dstLocation = [[[MKMapItem alloc] initWithPlacemark:dstPlaceMark] autorelease];
                [MKMapItem openMapsWithItems:[NSArray arrayWithObjects:srcLocation, dstLocation, nil]
                               launchOptions:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:MKLaunchOptionsDirectionsModeDriving, [NSNumber numberWithBool:YES], nil]
                                                                         forKeys:[NSArray arrayWithObjects:MKLaunchOptionsDirectionsModeKey, MKLaunchOptionsShowsTrafficKey, nil]]];
            } else {
                NSString *urlF  = @"http://maps.google.com/maps?daddr=%f,%f&saddr=%f,%f";
                [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[NSString stringWithFormat:urlF,
                                                                                 srcPoi.latitude, srcPoi.longitude,
                                                                                 dstPoi.latitude, dstPoi.longitude ]]];
            }
        }
    }
}

- (void)mapView:(MAMapView *)mapView didSingleTappedAtCoordinate:(CLLocationCoordinate2D)coordinate {
    NSString *jsObjectF =
    @"{var plus = %@;var args = new plus.maps.Point(%f,%f);\
    plus.maps.__bridge__.execCallback('%@', {callbackType:'click',payload:args});}";
    NSString *javaScript = [NSString stringWithFormat:jsObjectF, [H5CoreJavaScriptText plusObject], coordinate.longitude, coordinate.latitude, self.UUID];
    [jsBridge asyncWriteJavascript:javaScript];
}

//- (void)mapView:(MAMapView *)mapView didTouchPois:(NSArray *)pois{
//    CLLocationCoordinate2D coordiante = {0, 0};
//    
//    if ( [pois count] > 0 ) {
//      //  MATouchPoi *poi = [pois objectAtIndex:0];
//      //  coordiante = poi.coordinate;
//    }
//    NSString *jsObjectF =
//    @"var args = new plus.maps.Point(%f,%f);\
//    window.plus.maps.__bridge__.execCallback('%@', args);";
//    NSString *javaScript = [NSString stringWithFormat:jsObjectF, coordiante.longitude, coordiante.latitude, self.UUID];
//    [jsBridge asyncWriteJavascript:javaScript];
//}

@end


/*
 *------------------------------------------------
 *@ UIImage(InternalMethod)
 * 添加旋转图片的功能
 ------------------------------------------------
 */
#pragma mark ------------------------
@implementation UIImage(InternalMethod)

/*
 *------------------------------------------------
 *@summay: 自动获取高清图片接口
 *@param filepath NSString*文件按路径
 *@return
 *    UIImage*
 *@remark
 *------------------------------------------------
 */
+ (UIImage*)getRetainImage:(NSString *)filepath
{
    if ( filepath ){
        NSURL *loadUrl = nil;
        if ( [filepath hasPrefix:@"http://"]
            ||[filepath hasPrefix:@"file://"]) {
            loadUrl = [NSURL URLWithString:filepath];
        } else {
            loadUrl = [NSURL fileURLWithPath:filepath];
        }
        if ( loadUrl ) {
            if ( [[filepath lastPathComponent ] rangeOfString:@"@2x"].length
                ||  [[filepath lastPathComponent ] rangeOfString:@"@3x"].length)
            {
                if ([UIImage instancesRespondToSelector:@selector(initWithData:scale:)])
                {
                    return [UIImage imageWithData:[NSData dataWithContentsOfURL:loadUrl] scale:[UIScreen mainScreen].scale];
                }
                else
                {
                    UIImage *img = [UIImage imageWithData:[NSData dataWithContentsOfURL:loadUrl]];
                    return [UIImage imageWithCGImage:img.CGImage scale:[UIScreen mainScreen].scale orientation:img.imageOrientation];
                }
            }
            return [UIImage imageWithData:[NSData dataWithContentsOfURL:loadUrl]];
        }
    }
    return nil;
}
@end
