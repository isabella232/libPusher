//
//  PTPusher.m
//  PusherEvents
//
//  Created by Luke Redpath on 22/03/2010.
//  Copyright 2010 LJR Software Limited. All rights reserved.
//

#import "PTPusher.h"
#import "PTEventListener.h"
#import "PTPusherEvent.h"
#import "PTPusherChannel.h"
#import "PTPusherEventDispatcher.h"
#import "PTTargetActionEventListener.h"


NSURL *PTPusherConnectionURL(NSString *host, int port, NSString *key, NSString *clientID);

NSString *const PTPusherDataKey = @"data";
NSString *const PTPusherEventKey = @"event";
NSString *const PTPusherEventReceivedNotification = @"PTPusherEventReceivedNotification";

NSURL *PTPusherConnectionURL(NSString *host, int port, NSString *key, NSString *clientID)
{
  NSString *URLString = [NSString stringWithFormat:@"ws://%@:%d/app/%@?client=%@", host, port, key, clientID];
  return [NSURL URLWithString:URLString];
}

#define kPTPusherDefaultReconnectDelay 5.0

@interface PTPusher ()
@property (nonatomic, retain) PTPusherConnection *connection;
@end

#pragma mark -

@implementation PTPusher

@synthesize connection = _connection;
@synthesize delegate;
@synthesize reconnectAutomatically;
@synthesize reconnectDelay;

- (id)initWithConnection:(PTPusherConnection *)connection connectAutomatically:(BOOL)connectAutomatically
{
  if (self = [super init]) {
    dispatcher = [[PTPusherEventDispatcher alloc] init];
    channels = [[NSMutableDictionary alloc] init];

    self.connection = connection;
    self.connection.delegate = self;
    
    self.reconnectAutomatically = NO;
    self.reconnectDelay = kPTPusherDefaultReconnectDelay;
    
    if (connectAutomatically) {
      [self.connection connect];
    }
  }
  return self;
}

+ (id)pusherWithKey:(NSString *)key
{
  PTPusherConnection *connection = [[PTPusherConnection alloc] initWithURL:PTPusherConnectionURL(@"ws.pusherapp.com", 80, key, @"libpusher")];
  PTPusher *pusher = [[self alloc] initWithConnection:connection connectAutomatically:YES];
  [connection release];
  return [pusher autorelease];
}

- (void)dealloc;
{
  [channels release];
  [_connection disconnect];
  [_connection release];
  [super dealloc];
}

- (BOOL)isConnected
{
  return [self.connection isConnected];
}

#pragma mark - Binding to events

- (void)bindToEventNamed:(NSString *)eventName target:(id)target action:(SEL)selector
{
  [dispatcher addEventListenerForEventNamed:eventName target:target action:selector];
}

#pragma mark - Subscribing to channels

- (PTPusherChannel *)subscribeToChannelNamed:(NSString *)name
{
  PTPusherChannel *channel = [channels objectForKey:name];
  
  if (channel == nil) {
    channel = [[[PTPusherChannel alloc] initWithName:name pusher:self] autorelease];
    [channels setObject:channels forKey:name];
  }
  return channel;
}

- (PTPusherChannel *)subscribeToPrivateChannelNamed:(NSString *)name
{
  return [self subscribeToChannelNamed:[NSString stringWithFormat:@"private-%@", name]];
}

- (PTPusherChannel *)subscribeToPresenceChannelNamed:(NSString *)name
{
  return [self subscribeToChannelNamed:[NSString stringWithFormat:@"presence-%@", name]];
}

#pragma mark - PTPusherConnection delegate methods

- (void)pusherConnectionDidConnect:(PTPusherConnection *)connection
{
  if ([self.delegate respondsToSelector:@selector(pusher:connectionDidConnect:)]) {
    [self.delegate pusher:self connectionDidConnect:connection];
  }
}

- (void)pusherConnectionDidDisconnect:(PTPusherConnection *)connection
{
  if ([self.delegate respondsToSelector:@selector(pusher:connectionDidDisconnect:)]) {
    [self.delegate pusher:self connectionDidDisconnect:connection];
  }
  
  if (self.shouldReconnectAutomatically) {
    if ([self.delegate respondsToSelector:@selector(pusher:connectionWillReconnect:afterDelay:)]) {
      [self.delegate pusher:self connectionWillReconnect:connection afterDelay:self.reconnectDelay];
    }
    
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, self.reconnectDelay * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
      [connection connect];
    });
  }
}

- (void)pusherConnection:(PTPusherConnection *)connection didFailWithError:(NSError *)error
{
  if ([self.delegate respondsToSelector:@selector(pusher:connectionDidDisconnect:)]) {
    [self.delegate pusher:self connectionDidDisconnect:connection];
  }
}

- (void)pusherConnection:(PTPusherConnection *)connection didReceiveEvent:(PTPusherEvent *)event
{
  if (event.channel) {
    [[channels objectForKey:event.channel] dispatchEvent:event];
  }
  [dispatcher dispatchEvent:event];
  
  [[NSNotificationCenter defaultCenter] 
        postNotificationName:PTPusherEventReceivedNotification 
                      object:event];
}

@end

#pragma mark -

@implementation PTPusher (SharedFactory)

static NSString *sharedKey = nil;
static NSString *sharedSecret = nil;
static NSString *sharedAppID = nil;

+ (void)setKey:(NSString *)apiKey;
{
  [sharedKey autorelease]; sharedKey = [apiKey copy];
}

+ (void)setSecret:(NSString *)secret;
{
  [sharedSecret autorelease]; sharedSecret = [secret copy];
}

+ (void)setAppID:(NSString *)appId;
{
  [sharedAppID autorelease]; sharedAppID = [appId copy];
}

@end
