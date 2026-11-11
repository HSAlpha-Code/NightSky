I’m adding a new mode to my existing night-sky app (Flutter app, Django backend). It’s a Sky Map-style experience with my own twist. First read the codebase and follow its conventions. How you design and architect this is up to you. Be creative, and make the decisions you think give the best result.

The idea
Sky View shows the night sky in 3D, driven by the phone’s orientation sensors, so the camera isn’t needed. That makes the app useful on phones with bad cameras. The user points their phone at the sky and sees a virtual sky for their location and time, aligned with what’s really overhead.

The background is the Mellinger Milky Way panorama, downloaded once and shipped inside the app, so the mode works fully offline. On top of it the app overlays the things people expect from a sky map: stars, constellations, planets, the Sun and the Moon, with labels.

What I want from the experience

It feels like looking through a window at the real sky: smooth, responsive and accurate to where things actually are.
It works with no network and with no camera permission.
It runs well on low-end phones, with a sensible default for quality.
It handles weak or missing sensors gracefully, with calibration help and a manual drag fallback.
Users can change the time to see the sky earlier or later, and set their location manually if GPS isn’t available.
Tapping an object tells the user about it. If the object has Curated Cosmic Highlights (a feature I’m adding separately), link to them.
Users can find an object: the app guides them to turn the phone toward it.
The app size stays reasonable. Process the Mellinger image into whatever app-ready format you think is best, and tell me the final size.

Constraints

The existing camera flow must keep working unchanged. Sky View is a new mode alongside it, so decide where it fits best in the navigation and settings.
Credit Mellinger in the app. I need to verify his license terms before release, so leave a clear note about that in the README.
Coordinate math must be correct, so add tests with known cases (for example, Polaris’ altitude equals the latitude), and verify the panorama is aligned with the star data.
Use data sources for stars and constellations that are license-compatible, and record where each came from.

How to work
Deliver in small steps, starting with a minimal working version (sky sphere plus sensor orientation), then layering on the rest. After each step, list what you changed and flag any decision that needs my input. I have a limited token budget, so avoid re-reading large files and don’t paste large assets or catalogs into the chat.