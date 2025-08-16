(function() {
	'use strict'

	let attempts = 0
	const maxAttempts = 5

	/**
	 *
	 */
	function registerCameraRawViewer() {
		if (!window.OCA?.Viewer?.registerHandler) {
			if (attempts++ < maxAttempts) {
				// Exponential backoff: 100ms, 200ms, 400ms, 800ms, 1600ms
				setTimeout(registerCameraRawViewer, 100 * Math.pow(2, attempts - 1))
			} else {
				console.error('Camera Raw Previews: Could not register viewer handler after ' + maxAttempts + ' attempts. Viewer not available.')
			}
			return
		}

		try {
			OCA.Viewer.registerHandler({
				id: 'camerarawpreviews',
				mimesAliases: {
					'image/x-dcraw': 'image/jpeg',
					'image/x-indesign': 'image/jpeg',
				},
			})
			console.log('Camera Raw Previews: Successfully registered viewer handler')
		} catch (error) {
			console.error('Camera Raw Previews: Failed to register viewer handler', error)
		}
	}

	// Start registration process
	registerCameraRawViewer()
})()
