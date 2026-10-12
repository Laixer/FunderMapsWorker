import {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  DeleteObjectCommand,
} from "@aws-sdk/client-s3";
import { env } from "../config.ts";
import { withRetry } from "../lib/util.ts";

const client = new S3Client({
  endpoint: env.FUNDERMAPS_S3_ENDPOINT,
  region: env.FUNDERMAPS_S3_REGION,
  credentials: {
    accessKeyId: env.FUNDERMAPS_S3_ACCESS_KEY,
    secretAccessKey: env.FUNDERMAPS_S3_SECRET_KEY,
  },
  forcePathStyle: true,
});

export async function uploadFile(
  filePath: string,
  key: string,
  bucket?: string,
  extraArgs?: Record<string, string>
): Promise<void> {
  const body = await Bun.file(filePath).arrayBuffer();
  await uploadBytes(new Uint8Array(body), key, bucket, extraArgs);
}

export async function uploadBytes(
  body: Uint8Array,
  key: string,
  bucket?: string,
  extraArgs?: Record<string, string>
): Promise<void> {
  await withRetry(async () => {
    await client.send(
      new PutObjectCommand({
        Bucket: bucket ?? env.FUNDERMAPS_S3_BUCKET,
        Key: key,
        Body: body,
        ...extraArgs,
      })
    );
  });
}

export async function downloadBytes(
  key: string,
  bucket?: string
): Promise<Uint8Array> {
  return withRetry(async () => {
    const response = await client.send(
      new GetObjectCommand({
        Bucket: bucket ?? env.FUNDERMAPS_S3_BUCKET,
        Key: key,
      })
    );
    return response.Body!.transformToByteArray();
  });
}

export async function downloadFile(
  filePath: string,
  key: string,
  bucket?: string
): Promise<void> {
  await Bun.write(filePath, await downloadBytes(key, bucket));
}

export async function deleteFile(
  key: string,
  bucket?: string
): Promise<void> {
  await withRetry(async () => {
    await client.send(
      new DeleteObjectCommand({
        Bucket: bucket ?? env.FUNDERMAPS_S3_BUCKET,
        Key: key,
      })
    );
  });
}
