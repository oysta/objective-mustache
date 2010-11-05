/*
 Copyright (c) 2010 Navel Labs, Ltd.

 Permission is hereby granted, free of charge, to any person
 obtaining a copy of this software and associated documentation
 files (the "Software"), to deal in the Software without
 restriction, including without limitation the rights to use,
 copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the
 Software is furnished to do so, subject to the following
 conditions:

 The above copyright notice and this permission notice shall be
 included in all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 OTHER DEALINGS IN THE SOFTWARE.
 */

#import "NLObjectiveMustache.h"


@interface NLArrayStack : NSObject
{
    NSMutableArray *stackArray;
}

- (void)push:(id)item;
- (id)pop;
- (id)peek;

@end


@implementation NLArrayStack

- (id)init
{
    if (self = [super init]) {
        stackArray = [[NSMutableArray array] retain];
    }
    return self;
}

- (void)push:(id)item
{
    [stackArray addObject:item];
}

- (id)pop
{
    id item = [self peek];
    if (item) { 
        [[item retain] autorelease];
        [stackArray removeLastObject];
    }
    return item;
}

- (id)peek
{
    return [stackArray lastObject];
}

- (void)dealloc
{
    [stackArray release];
    [super dealloc];
}

@end


// Creates a parent-child relationship for key lookups using KVC.
// If the child does not contain the requested key, its parent is 
// queried for it.
@interface NLKeyValueChain : NSObject
{
    id parent;
    id object;
}

+ (id)chainObject:(id)object withParent:(id)parent;

- (id)initWithObject:(id)object parent:(id)parent;

@end


@implementation NLKeyValueChain

+ (id)chainObject:(id)object withParent:(id)parent {
    return [[[NLKeyValueChain alloc] initWithObject:object parent:parent] autorelease];
}

- (id)initWithObject:(id)newObject parent:(id)newParent
{
    if (self = [super init]) {
        parent = [newParent retain];
        object = [newObject retain];
    }
    return self;
}

- (id)valueForKey:(id)key
{
    id value = [object valueForKey:key];
    if (!value) {
        value = [parent valueForKey:key];
    }
    return value;
}

- (void)dealloc
{
    [parent release];
    [object release];
    [super dealloc];
}

@end




@interface NLTemplateRenderContext : NSObject
{
    id parentView;
    id currentView;
    NSEnumerator *enumerator;
    NSUInteger templateLocation;
}

- (id)initWithEnumerator:(NSEnumerator *)newEnumerator atLocation:(NSUInteger)newLocation parentView:(id)newParentView;
- (id)initWithView:(id)newView atLocation:(NSUInteger)newLocation parentView:(id)newParentView; 

- (void)nextView;

@property (readonly) NSUInteger templateLocation;
@property (readonly) id currentView;

@end


@implementation NLTemplateRenderContext

@synthesize templateLocation, currentView;

- (id)initWithEnumerator:(NSEnumerator *)newEnumerator atLocation:(NSUInteger)newLocation parentView:(id)newParentView
{
    if (self = [self initWithView:[newEnumerator nextObject] atLocation:newLocation parentView:newParentView]) {
        enumerator = [newEnumerator retain];
    }
    return self;
}

- (id)initWithView:(id)newView atLocation:(NSUInteger)newLocation parentView:(id)newParentView
{
    if (self = [self init]) {
        currentView = [newView retain];
        parentView = [newParentView retain];
        templateLocation = newLocation;
    }
    return self;
}

- (void)nextView
{
    id nextView = [enumerator nextObject];
    if (nextView) {
        nextView = [NLKeyValueChain chainObject:nextView withParent:parentView]; 
    }

    [currentView release];
    currentView = [nextView retain];
}

- (void)dealloc
{
    [enumerator release];
    [parentView release];
    [currentView release];
    [super dealloc];
}

@end




@interface NLObjectiveMustache ()

@property (retain) NLArrayStack *renderContextStack;

@end



@implementation NLObjectiveMustache


@synthesize templateStr;
@synthesize scanner;
@synthesize results;
@synthesize renderContextStack;


- (void)dealloc
{
    self.templateStr = nil;
    self.scanner = nil;
    self.results = nil;
    self.renderContextStack = nil;
    [super dealloc];
}


- (NSScanner *)scanner
{
    if (!scanner) {
        scanner = [[NSScanner scannerWithString:templateStr] retain];
        [scanner setCharactersToBeSkipped:nil];
    }
    return scanner;
}


- (id)context
{
    NLTemplateRenderContext *renderContext = (NLTemplateRenderContext *) [renderContextStack peek];
    return [renderContext currentView];
}


- (NLTemplateRenderContext *)getRenderContextForEnumerator:(NSEnumerator *)enumerator
{
    NSUInteger location = [scanner scanLocation];
    return [[[NLTemplateRenderContext alloc] initWithEnumerator:enumerator atLocation:location parentView:self.context] autorelease];
}


+ (NSString *)escape:(NSString *)string
{
    NSString *result = [string stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    result = [result stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    result = [result stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
    result = [result stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
    return result;
}


+ (NSString *)escapeAndLineBreak:(NSString *)string
{
    NSString *result = [self escape:string];
    return [result stringByReplacingOccurrencesOfString:@"\n" withString:@"<br>"];
}


- (NSString *)escape:(NSString *)string
{
    return [[self class] escape:string];
}


- (void)scanToNextInterpolation
{
    NSString *lastFind = nil;
    if ([scanner scanUpToString:@"{{" intoString:&lastFind]) {
        [results appendString:lastFind];
    }
    [scanner scanString:@"{{" intoString:nil];
}


- (void)processSectionWithKey:(NSString *)key
{
    id interpolatedValue = [self.context valueForKey:key];

    if ([interpolatedValue respondsToSelector:@selector(objectEnumerator)]) {
        NLTemplateRenderContext *renderContext = [self getRenderContextForEnumerator:[interpolatedValue objectEnumerator]];
        if ([renderContext currentView]) {
            [renderContextStack push:renderContext];
            return;
        }          
    } else if ([interpolatedValue boolValue]) {
        return;
    }

    // Nothing to process in this section -- skip to the ending sigil
    NSString *endingSigil = [NSString stringWithFormat:@"{{/%@}}", key];
    [scanner scanUpToString:endingSigil intoString:nil];
}

- (void)processSigil
{
    NSString *lastFind = nil;
    [scanner scanUpToString:@"}}" intoString:&lastFind];

    NSString *firstChar = [lastFind substringToIndex:1];
    NSString *interpolatedValue = nil;
    if ([firstChar isEqualToString:@"#"]) {

        NSString *key = [lastFind substringFromIndex:1];
        [self processSectionWithKey:key];

    } else if ([firstChar isEqualToString:@"{"]) {

        NSString *key = [lastFind substringFromIndex:1];
        interpolatedValue = [self.context valueForKey:key];
        if (interpolatedValue) {
            [results appendString:[NSString stringWithFormat:@"%@", interpolatedValue]];
        }
        [scanner scanString:@"}" intoString:nil];

    } else if ([firstChar isEqualToString:@"/"]) {

        NLTemplateRenderContext *renderContext = (NLTemplateRenderContext *) [renderContextStack peek];
        [renderContext nextView];
        if (self.context) {
            // Still more items to render for this section - loop the section again
            [scanner setScanLocation:renderContext.templateLocation];
        }
        else {
            // Restore previous view
            [renderContextStack pop];
        }

    } else {

        interpolatedValue = [self.context valueForKey:lastFind];
        if (interpolatedValue) {
            [results appendString:[self escape:[NSString stringWithFormat:@"%@", interpolatedValue]]];
        }
    }

    [scanner scanString:@"}}" intoString:nil];
}


- (NSString *)renderWithView:(id)view
{
    self.results = [NSMutableString stringWithCapacity:500];
    self.scanner = nil;
    self.scanner; // Spins up a new copy

    self.renderContextStack = [[NLArrayStack new] autorelease];
    [renderContextStack push:[[[NLTemplateRenderContext alloc] initWithView:view atLocation:0 parentView:nil] autorelease]];

    while ([scanner isAtEnd] == NO) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

        [self scanToNextInterpolation];

        if (![scanner isAtEnd]) {
            [self processSigil];
        }

        [pool drain];
    }

    self.scanner = nil;

    return self.results;
}


+ (NSString *)stringFromTemplate:(NSString *)template view:(id)view
{
    NLObjectiveMustache *mustache = [[NLObjectiveMustache alloc] init];
    mustache.templateStr = template;
    NSString *result = [mustache renderWithView:view];
    [mustache release];
    return result;
}


+ (NSString *)stringFromTemplateNamed:(NSString *)templateName view:(id)view
{
    NSError *error;
    NSString *filePath = [[NSBundle mainBundle] pathForResource:templateName ofType:@"mustache"];
    NSString *fileTemplate = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:&error];
    NSString *html = [NLObjectiveMustache stringFromTemplate:fileTemplate view:view];

    return html;
}


@end
