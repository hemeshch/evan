// Simple fetch-based upload for icon.png
async function uploadIcon() {
    try {
        // Read the file
        const fileInput = document.createElement('input');
        fileInput.type = 'file';

        // For browser environment, you'd select the file
        // For this example, we'll use fetch to get the icon.png
        const response = await fetch('./icon.png');
        const blob = await response.blob();

        const formData = new FormData();
        formData.append('file', blob, 'icon.png');

        console.log('Uploading icon.png...');

        const uploadResponse = await fetch('https://YOUR_FILE_UPLOAD_API.workers.dev/upload', {
            method: 'POST',
            body: formData
        });

        const result = await uploadResponse.json();

        if (result.success) {
            console.log('✅ Upload successful!');
            console.log('📁 File Name:', result.fileName);
            console.log('📏 File Size:', (result.size / 1024).toFixed(2), 'KB');
            console.log('🔗 Download URL:', result.supabaseUrl);

            return result.supabaseUrl;
        } else {
            console.log('❌ Upload failed:', result.error);
        }

    } catch (error) {
        console.log('❌ Error:', error.message);
    }
}

// Run the upload
uploadIcon();