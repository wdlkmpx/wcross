// https://www.maheshsubramaniya.com/article/hello-world-in-objective-c-and-compiling-with-gcc.html

// Alpine: compiles but segfaults, need GNUstep
// https://stackoverflow.com/questions/16064486/new-to-objective-c-getting-a-may-not-respond-to-new-warning-constructor

#import <objc/Object.h>

#import <stdio.h>

@interface HelloWorld:Object
{
}
-(void) hello;
@end


@implementation HelloWorld
-(void) hello
{
    printf("Hello World");
}
@end


int main(int argv, char* argc[])
{
    id o = [HelloWorld new];

    [o hello];
}
