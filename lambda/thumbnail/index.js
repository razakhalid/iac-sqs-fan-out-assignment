const AWS = require('aws-sdk');
const sharp = require('sharp');
const s3 = new AWS.S3();

exports.handler = async (event) => {
  for (const record of event.Records) {
    const body = JSON.parse(record.body);
    const snsMessage = JSON.parse(body.Message);
    
    // Extract S3 info
    const bucket = snsMessage.Records[0].s3.bucket.name;
    const key = decodeURIComponent(snsMessage.Records[0].s3.object.key.replace(/\+/g, ' '));
    
    try {
      // Get image from S3
      const s3Object = await s3.getObject({
        Bucket: bucket,
        Key: key
      }).promise();
      
      // Generate thumbnail with Sharp
      const thumbnailBuffer = await sharp(s3Object.Body)
        .resize(200, 200)
        .toBuffer();
      
      // Upload thumbnail to output bucket
      await s3.putObject({
        Bucket: process.env.OUTPUT_BUCKET,
        Key: `thumbnails/${key}`,
        Body: thumbnailBuffer,
        ContentType: 'image/jpeg'
      }).promise();
      
      console.log(`Successfully processed ${key}`);
    } catch (error) {
      console.error(`Error processing ${key}: ${error}`);
      throw error;
    }
  }
};