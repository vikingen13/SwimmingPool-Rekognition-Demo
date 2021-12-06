projectArn = aws rekognition describe-projects --project-names SwimmingPoolProject --query "ProjectDescriptions[0].ProjectArn" --output text
trainDS = aws rekognition describe-projects --project-names SwimmingPoolProject --query "ProjectDescriptions[0].Datasets[?DatasetType=='TRAIN'].DatasetArn" --output text
testDS = aws rekognition describe-projects --project-names SwimmingPoolProject --query "ProjectDescriptions[0].Datasets[?DatasetType=='TEST'].DatasetArn" --output text

all: createbucket preparedataset copydataset createproject insertdatasetinproject wait distributedatasets wait trainmodel deploy-site

createbucket:
	aws s3 mb s3://$(s3artifact)

preparedataset:
	sed -i '' 's/bucket_name/$(s3artifact)/g' dataset-labelled/output.manifest

copydataset:
	aws s3 sync dataset-labelled/ s3://$(s3artifact)/dataset-labelled

createproject:
	aws cloudformation deploy --template-file main.yaml --stack-name swimmingPoolRekognition --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND
	
insertdatasetinproject:
	aws rekognition create-dataset --project-arn $$($(projectArn)) \
  		--dataset-type TRAIN \
  		--dataset-source '{ "GroundTruthManifest": { "S3Object": { "Bucket": "$(s3artifact)", "Name": "dataset-labelled/output.manifest" } } }' \
		--query "DatasetArn" --output text

	aws rekognition create-dataset --project-arn $$($(projectArn)) \
  		--dataset-type TEST \
		--query "DatasetArn" --output text

wait:
	echo "we stop for 60s to wait for dataset creation/distribution"
	sleep 60

distributedatasets:	
	eval aws rekognition distribute-dataset-entries --datasets [\'{\"Arn\": \"$$($(trainDS))\"}, {\"Arn\": \"$$($(testDS))\"}\']

trainmodel:
	aws rekognition create-project-version\
                            --project-arn $$($(projectArn)) \
                            --version-name "v1"\
                            --output-config '{"S3Bucket":"$(s3artifact)", "S3KeyPrefix":"output_folder"}'

deploy-site:
	aws cloudformation deploy --template-file WebSite.yaml --stack-name websiteRekognition --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND --parameter-overrides AdminEmail=$(email)

