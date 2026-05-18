import {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  DeleteObjectCommand,
} from "@aws-sdk/client-s3";
import { relative } from "node:path";
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

export async function downloadFile(
  filePath: string,
  key: string,
  bucket?: string
): Promise<void> {
  await withRetry(async () => {
    const response = await client.send(
      new GetObjectCommand({
        Bucket: bucket ?? env.FUNDERMAPS_S3_BUCKET,
        Key: key,
      })
    );
    const bytes = await response.Body!.transformToByteArray();
    await Bun.write(filePath, bytes);
  });
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

export async function uploadDirectory(
  directoryPath: string,
  keyPrefix: string,
  bucket?: string,
  extraArgs?: Record<string, string>
): Promise<number> {
  const glob = new Bun.Glob("**/*");
  const files: string[] = [];
  for await (const path of glob.scan({ cwd: directoryPath, absolute: true, onlyFiles: true })) {
    files.push(path);
  }

  const concurrency = 10;
  let uploaded = 0;

  for (let i = 0; i < files.length; i += concurrency) {
    const batch = files.slice(i, i + concurrency);
    await Promise.all(
      batch.map(async (filePath) => {
        const rel = relative(directoryPath, filePath);
        const s3Key = keyPrefix ? `${keyPrefix}/${rel}` : rel;
        await uploadFile(filePath, s3Key, bucket, extraArgs);
        uploaded++;
      })
    );
  }

  if (uploaded !== files.length) {
    throw new Error(
      `Failed to upload all files: ${uploaded}/${files.length}`
    );
  }

  return uploaded;
}
