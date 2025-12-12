package storage

import (
	"context"
	"fmt"
	"log"
	"net/url"
	"time"

	"github.com/grafikarsa/backend/internal/config"
	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

type MinIOClient struct {
	client      *minio.Client
	bucket      string
	publicURL   string
	presignHost string
}

func NewMinIOClient(cfg *config.Config) (*MinIOClient, error) {
	minioCfg := cfg.MinIO
	client, err := minio.New(minioCfg.Endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(minioCfg.AccessKey, minioCfg.SecretKey, ""),
		Secure: minioCfg.UseSSL,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to create MinIO client: %w", err)
	}

	ctx := context.Background()
	exists, err := client.BucketExists(ctx, minioCfg.Bucket)
	if err != nil {
		return nil, fmt.Errorf("failed to check bucket: %w", err)
	}

	if !exists {
		err = client.MakeBucket(ctx, minioCfg.Bucket, minio.MakeBucketOptions{})
		if err != nil {
			return nil, fmt.Errorf("failed to create bucket: %w", err)
		}
		log.Printf("Bucket %s created successfully", minioCfg.Bucket)
	}

	return &MinIOClient{
		client:      client,
		bucket:      minioCfg.Bucket,
		publicURL:   minioCfg.PublicURL,
		presignHost: minioCfg.PresignHost,
	}, nil
}

func (m *MinIOClient) GetPresignedPutURL(objectKey, contentType string, expiry time.Duration) (string, error) {
	presignedURL, err := m.client.PresignedPutObject(
		context.Background(),
		m.bucket,
		objectKey,
		expiry,
	)
	if err != nil {
		return "", fmt.Errorf("failed to generate presigned URL: %w", err)
	}

	// Replace internal hostname with presign host for browser access
	urlStr := presignedURL.String()
	if m.presignHost != "" && presignedURL.Host != m.presignHost {
		presignedURL.Host = m.presignHost
		urlStr = presignedURL.String()
	}

	return urlStr, nil
}

func (m *MinIOClient) GetPresignedGetURL(objectKey string, expiry time.Duration) (string, error) {
	reqParams := make(url.Values)
	presignedURL, err := m.client.PresignedGetObject(
		context.Background(),
		m.bucket,
		objectKey,
		expiry,
		reqParams,
	)
	if err != nil {
		return "", fmt.Errorf("failed to generate presigned URL: %w", err)
	}
	return presignedURL.String(), nil
}

func (m *MinIOClient) ObjectExists(objectKey string) (bool, error) {
	_, err := m.client.StatObject(context.Background(), m.bucket, objectKey, minio.StatObjectOptions{})
	if err != nil {
		errResponse := minio.ToErrorResponse(err)
		if errResponse.Code == "NoSuchKey" {
			return false, nil
		}
		return false, err
	}
	return true, nil
}

func (m *MinIOClient) DeleteObject(objectKey string) error {
	return m.client.RemoveObject(context.Background(), m.bucket, objectKey, minio.RemoveObjectOptions{})
}

func (m *MinIOClient) GetPublicURL(objectKey string) string {
	return fmt.Sprintf("%s/%s", m.publicURL, objectKey)
}
