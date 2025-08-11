	// Enhanced viewer registration for camera raw previews
	function registerCameraRawViewer() {
		if (!window.OCA || !window.OCA.Viewer) {
			console.warn('Camera Raw Previews: OCA.Viewer not available, retrying...');
			return false;
		}

		if (typeof OCA.Viewer.registerHandler !== 'function') {
			console.error('Camera Raw Previews: OCA.Viewer.registerHandler is not a function');
			return false;
		}

		try {
			OCA.Viewer.registerHandler({
				id: 'camerarawpreviews',
				// Handle both raw images and InDesign files
				mimesAliases: {
					'image/x-dcraw': 'image/jpeg',
					'image/x-indesign': 'image/jpeg'
				},
				// Add explicit extensions for better compatibility
				extensions: ['cr2', 'cr3', 'crw', 'dng', 'nef', 'nrw', 'arw', 'srf', 'sr2', 'srw', 'orf', 'rw2', 'pef', 'raf', 'mrw', '3fr', 'fff', 'erf', 'iiq', 'kdc', 'rwl', 'x3f', 'ori', 'tif', 'tiff', 'indd']
			});
			console.log('Camera Raw Previews: Viewer handler registered successfully');
			return true;
		} catch (error) {
			console.error('Camera Raw Previews: Error registering viewer handler:', error);
			return false;
		}
	}

	// Try to register immediately
	if (!registerCameraRawViewer()) {
		// If immediate registration fails, wait for DOM content loaded
		document.addEventListener('DOMContentLoaded', function() {
			if (!registerCameraRawViewer()) {
				// If still fails, try after a short delay to ensure OCA.Viewer is loaded
				setTimeout(registerCameraRawViewer, 1000);
			}
		});
	}

