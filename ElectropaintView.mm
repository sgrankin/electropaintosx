/*
 * ElectropaintOSXView.mm
 * ElectropaintOSX
 *
 * Modifications for Universal Binary (Version 0.3)
 * 07/10/06 Alexander v. Below <alex@vonbelow.com>
 *
 * Modifications for antialiasing, VBL, parameter tweak.
 * Vincent Fiano <ynniv-ep@ynniv.com>
 *
 * http://www.lloydslounge.org/electropaintosx/
 *
 * Created by Douglas McInnes on 12/17/04.
 * Copyright (c) 2004, Kent RosenKoetter, Douglas McInnes.
 * All rights reserved.
 *
 * ported from Kent Rosenkoetter's electropaint.cpp:
 * http://legolas.homelinux.org/~kent/electropaint/
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 */

#import "ElectropaintView.h"

#include <OpenGL/gl.h>
#include <OpenGL/glu.h>
#include <GLUT/glut.h>
#include <OpenGL/OpenGL.h>

#include <cmath>
#include <cassert>
#include <climits>
#include <cstdlib>
#include <ctime>

#include <list>
#include <algorithm>
#include <functional>



struct Color {
	CGFloat red;
	CGFloat green;
	CGFloat blue;
	
	Color(void) : red(1), green(1), blue(1) { };
	Color(CGFloat r, CGFloat g, CGFloat b) : red(r), green(g), blue(b) { };
	Color(const Color & c) : red(c.red), green(c.green), blue(c.blue) { };
};


struct Wing
{
	CGFloat radius;		// all angles in degrees, per OpenGL
	CGFloat angle;
	CGFloat delta_angle;
	CGFloat z_delta;
	CGFloat roll;
	CGFloat pitch;
	CGFloat yaw;
	Color color;
	Color edge_color;
	CGFloat alpha;
	
	Wing(void) : radius(10), angle(0), delta_angle(15), z_delta(0.5),
	roll(0), pitch(0), yaw(0),
	color(), edge_color(), alpha(1)
	{ }
	Wing(CGFloat _rad, CGFloat _ang, CGFloat _dang, CGFloat _dz,
	     CGFloat _roll, CGFloat _pitch, CGFloat _yaw,
	     const Color & _c, const Color & _ec = Color(),
	     CGFloat _a = 1) : radius(_rad), angle(_ang), delta_angle(_dang), z_delta(_dz),
	roll(_roll), pitch(_pitch), yaw(_yaw),
	color(_c), edge_color(_ec),
	alpha(_a)
	{ }
};


struct RandomGenerator
{
	CGFloat min_value;
	CGFloat max_value;
	bool wrap;
	
	CGFloat max_acceleration;
	CGFloat max_speed;
	NSUInteger stability;
	
	RandomGenerator(CGFloat min, CGFloat max = 1.0,
			NSUInteger stab = 50,
			bool wr = false,
			CGFloat msp = 0.02,
			CGFloat macc = 0.005) : min_value(min), max_value(max),
	wrap(wr),
	max_acceleration(macc), max_speed(msp), stability(stab),
	value(0), delta(0), count(INT_MAX - 1),
	rand_state(0)
	{
	}
	
	CGFloat operator()(void)
	{
		if (++count > stability) {
			accel = getNewAccel();
			//			std::cout << accel << std::endl;
			count = 0;
		}
		delta += accel;
		delta = std::min(delta, max_speed);
		delta = std::max(delta, -max_speed);
		value += delta;
		if (wrap) {
			// fmodf
			value = remainderf(value - min_value, max_value - min_value) + min_value;
		} else {
			value = std::min(value, max_value);
			value = std::max(value, min_value);
		}
		return value;
	}
	
protected:
	CGFloat value;
	CGFloat delta;
	CGFloat accel;
	
	NSUInteger count;
	NSUInteger rand_state;
	CGFloat getNewAccel(void)
	{
		NSUInteger r(arc4random());
		CGFloat f = r / (RAND_MAX + 1.0f);
		f = (f - 0.5f) * 2.0f;
		f *= max_acceleration;
		return f;
	}
};

class Saver {
	GLuint wing_dl;
	std::list<Wing> wings;
	
	RandomGenerator red_movement{0.0, 1.0, 95};
	RandomGenerator green_movement{0.0, 1.0, 40};
	RandomGenerator blue_movement{0.0, 1.0, 70};
	RandomGenerator roll_change{0, 360, 80, true, 0.5, 0.125};
	RandomGenerator pitch_change{0, 360, 40, true, 1.0, 0.125};
	RandomGenerator yaw_change{0, 360, 50, true, 0.75, 0.125};
	RandomGenerator radius_change{-15, 15, 150, false, 0.05, 0.005};
	RandomGenerator angle_change{0, 360, 120, true, 1, 0.025};
	RandomGenerator delta_angle_change{0, 360, 80, true, 0.1, 0.01};
	RandomGenerator z_delta_change{0.4, 0.7, 200, false, 0.005, 0.0005};
	
public:
	void initGL() {
		GLint params[] = { 1 };
		CGLSetParameter(CGLGetCurrentContext(),  kCGLCPSwapInterval, params);
		
		glutInitDisplayMode(GLUT_RGBA | GLUT_DEPTH | GLUT_DOUBLE);
		
		glEnable (GL_DEPTH_TEST);
		glEnable (GL_NORMALIZE);
		
		glHint (GL_LINE_SMOOTH_HINT, GL_NICEST);
		glEnable (GL_LINE_SMOOTH);
		
		glEnable (GL_BLEND);
		glBlendFunc (GL_SRC_ALPHA, GL_ONE);
		
		glDepthMask(GL_FALSE);
		
#if defined(GL_VERSION_1_1)
		glPolygonOffset(-0.5, -2);
#endif
		
		wing_dl = glGenLists(1);
		glNewList(wing_dl, GL_COMPILE);
		glBegin(GL_QUADS);
		// default z-value is 0
		// default normal is (0, 0, 1);
		glVertex2f(1, 1);
		glVertex2f(-1, 1);
		glVertex2f(-1, -1);
		glVertex2f(1, -1);
		glEnd();
		glEndList();
		
		Wing newwing(radius_change(),
			     angle_change(),
			     delta_angle_change(),
			     z_delta_change(),
			     roll_change(),
			     pitch_change(),
			     yaw_change(),
			     Color(red_movement(),
				   green_movement(),
				   blue_movement()));
		wings.resize(40, newwing);
		
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	}
	
	void display() {
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
		glLoadIdentity();
		gluLookAt(0, 50, 50,
			  0, 0, 13,
			  0, 0, 1);
		
		std::list<Wing>::const_iterator i(wings.begin());
		std::list<Wing>::const_iterator end(wings.end());
		unsigned int count(0);
#if defined(GL_VERSION_1_1)
		glEnable(GL_POLYGON_OFFSET_LINE);
#endif
		glPushMatrix();
		while (i != end) {
			Wing wing(*i++);
			
			glTranslatef(0, 0, wing.z_delta);
			glPushMatrix();
			glRotatef(wing.angle + count * wing.delta_angle,0 , 0, 1);
			glTranslatef(wing.radius, 0, 0);
			glRotatef(-wing.yaw, 0, 0, 1);
			glRotatef(-wing.pitch, 0, 1, 0);
			glRotatef(wing.roll, 1, 0, 0);
			
			glDisable(GL_BLEND);
			glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
			glColor3f(wing.color.red, wing.color.green, wing.color.blue);
			glCallList(wing_dl);
			
			glEnable (GL_BLEND);
			glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
			glColor3f(wing.edge_color.red, wing.edge_color.green, wing.edge_color.blue);
			glCallList(wing_dl);
			
			glPopMatrix();
			
			count++;
		}
		glPopMatrix();
		glFlush();
		//checkGLErrors(std::cerr);
		glutSwapBuffers();
		
	}
	
	void reshape(NSSize size) {
		glViewport(0, 0, (int)size.width, (int)size.height);
		
		CGFloat xmult(1.0);
		CGFloat ymult(1.0);
		// float aspect(width / static_cast<float>(height));
		if (size.width > size.height) {
			xmult = size.width / size.height;
		} else {
			ymult = size.height / size.width;
		}
		
		glMatrixMode(GL_PROJECTION);
		glLoadIdentity();
		glOrtho(-20 * xmult, 20 * xmult,
			-20 * ymult, 20 * ymult,
			35, 105);
		glMatrixMode(GL_MODELVIEW);
		// checkGLErrors(std::cerr);
	}
	
	void animateOneFrame() {
		wings.pop_back();
		wings.push_front(Wing(radius_change(),
				      angle_change(),
				      delta_angle_change(),
				      z_delta_change(),
				      roll_change(),
				      pitch_change(),
				      yaw_change(),
				      Color(red_movement(),
					    green_movement(),
					    blue_movement())));
	}
};




@implementation ElectropaintView

/*****************************/
/* ScreenSaverView functions */
/*****************************/

- (id)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview {
	self = [super initWithFrame:frame isPreview:isPreview];
	if (self) {
		[self setAnimationTimeInterval:1.0/60.0];
		
		NSOpenGLPixelFormatAttribute attr[] = {
			NSOpenGLPFANoRecovery,
			NSOpenGLPFAAccelerated,
			NSOpenGLPFAColorSize, (NSOpenGLPixelFormatAttribute) 24,
			NSOpenGLPFAAlphaSize, (NSOpenGLPixelFormatAttribute) 8,
			NSOpenGLPFAStencilSize, (NSOpenGLPixelFormatAttribute) 0,
			// NSOpenGLPFAWindow,
			// use the defined value 80 for NSOpenGLFAWindow to avoid
			// deprication warnings
			(NSOpenGLPixelFormatAttribute) 80,
			(NSOpenGLPixelFormatAttribute) 0,
		};
		
		NSOpenGLPixelFormat *format = [[[NSOpenGLPixelFormat alloc] initWithAttributes:attr] autorelease];
		glview = [[NSOpenGLView alloc] initWithFrame: NSZeroRect
						 pixelFormat: format];
		/* enable OpenGL hi-res display support
		 https://developer.apple.com/library/archive/documentation/GraphicsAnimation/Conceptual/HighResolutionOSX/CapturingScreenContents/CapturingScreenContents.html#//apple_ref/doc/uid/TP40012302-CH10-SW35
		 */
		
		[glview setWantsBestResolutionOpenGLSurface: YES];
		saver = new Saver();
		
		[[glview openGLContext] makeCurrentContext];
		saver->initGL();
	}
	return self;
}

- (void)startAnimation {
	if (![glview isDescendantOf:self]) {
		[self addSubview:glview];
	}
	[super startAnimation];
}

- (void)stopAnimation {
	[super stopAnimation];
	[glview removeFromSuperview];
}

- (void)drawRect:(NSRect)rect {
	[super drawRect:rect];
}

- (void)animateOneFrame {
	[super animateOneFrame];
	saver->animateOneFrame();
	[[glview openGLContext] makeCurrentContext];
	saver->display();
}

- (BOOL)hasConfigureSheet { return NO; }
- (NSWindow*)configureSheet { return nil; }

- (void)setFrameSize:(NSSize)newSize {
	[glview setFrameSize:newSize];
	[[glview openGLContext] makeCurrentContext];
	saver->reshape(newSize);
	[[glview openGLContext] update];
	[super setFrameSize:newSize];
}

- (void)dealloc {
	if (saver) {
		delete saver;
		saver = nullptr;
	}
	[super dealloc];
}

@end
