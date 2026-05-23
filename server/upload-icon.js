// Node.js script to upload icon.png
import fs from 'fs';
import fetch from 'node-fetch';
import FormData from 'form-data';

async function uploadIcon() {
    try {
        // Read the icon.png file
        const fileBuffer = fs.readFileSync('./icon.png');

        // Create form data
        const formData = new FormData();
        formData.append('file', fileBuffer, {
            filename: 'icon.png',
            contentType: 'image/png'
        });

        console.log('Uploading icon.png...');

        // Upload to your worker. Set FILE_UPLOAD_API_URL or edit inline.
        const uploadUrl = process.env.FILE_UPLOAD_API_URL || 'https://YOUR_FILE_UPLOAD_API.workers.dev/upload';
        const response = await fetch(uploadUrl, {
            method: 'POST',
            body: formData
        });

        const result = await response.json();

        if (result.success) {
            console.log('✅ Upload successful!');
            console.log('📁 File Name:', result.fileName);
            console.log('📏 File Size:', (result.size / 1024).toFixed(2), 'KB');
            console.log('🔗 Download URL:', result.supabaseUrl);
            console.log('📊 File Info URL:', result.downloadUrl);
        } else {
            console.log('❌ Upload failed:', result.error);
        }

    } catch (error) {
        console.log('❌ Error:', error.message);
    }
}

uploadIcon();