#!/bin/bash

#Script to setup compute resources and then create compute resources up to do some work, and it mounts the NFS mountpoint using startup script
#Make sure the gcloud SDK is installed on this server
#It is also assumed that you have some familiarity with GCP console and that Dell Technologies PowerScale cluster is installed and ready for creating nfs exports



#Check if gcloud is available
printf "Let's first check if gcloud is installed, and if not we'll quit\n\n"
/usr/bin/gcloud version
sleep 5
if [ $? -eq 0 ]
then
	printf "Looks like gcloud is installed, moving on\n\n"
else
	printf "Install gcloud first and then come back \n"
	exit 0
fi

printf "\nSetting region = us-east4, zone = us-east4-c, project = my-isilon-project\n"
printf "\nIf you need to change these, modify the values in the script\n"

gcloud config set compute/zone us-east4-c
gcloud config set compute/region us-east4
gcloud config set project my-isilon-project

gcloud config list
printf "\nAbove is your current config based on how you setup the gcloud: \n"
printf "We'll use set region/zone for creating compute instances. We suggest you keep the region/zone same as where you have the PowerScale cluster, which should be us-east4 at this time. \n\n"
sleep 7

#gcloud projects list
#printf "\nWhich of the above projects should we operate in?  type the name here: \n"
#read myproj
#printf "We'll use this project you provided, if you made a mistake, type ctrl+c: $myproj \n\n"
#sleep 5

#gcloud config set project $myproj

printf "\nEnter your domain userid: \n"
read domainid

#Gather all the data we need for creating a VM Instance Template
myzone=$(gcloud config get-value compute/zone 2> /dev/null)
myproject=$(gcloud config get-value core/project 2> /dev/null)
myregion=$(gcloud config get-value compute/region 2> /dev/null)

printf "\nWhat do you want to do? Enter setupenv or setupcompute: \n"
read ANS

	case $ANS in
	setupenv)

		#Make the bucket for any startup scripts
		#printf "Following buckets exist: \n"
		#gsutil ls
		#printf "Want to make a new bucket for storing your startup scripts for the compute instances? (yes/no): \n"
		#read mbans
		#if [ $mbans = yes ]
		#then
			#printf "Bucket name? Must be universally unique:  \n"
		#	read bname
		#	gsutil mb gs://$bname
		#	printf "Upload startup script in the bucket?
		#	read upload
		#	if [ $upload = yes ]
		#	then
		#		printf "Please provide the filename for the startup script file: \n"
		#		readfilename
		#		gsutil cp $readfilename gs://$bname
		#	fi
		#fi

		##############################
		#Instance Template Section
		##############################

		printf "\n\n"
		gcloud compute instance-groups list --format='value(name)'
		if [ $? -eq 1 ]
		then
			allcurrentmig=$(gcloud compute instance-groups list --format='value(name)' 2> /dev/null)
			printf "\nDo you want to delete the above managed instance group? Type "name_of_the_instancegroup" or "all":  \n"
			read delmigans
			if [ $delmigans = all]
			then
				gcloud compute instance-groups managed delete $allcurrentmig --region=$myregion
			else
				gcloud compute instance-groups managed delete $delmigans --region=$myregion
			fi
		fi

		printf "\nShowing you current instance templates \n"
		gcloud compute instance-templates list
		printf "\nWould you like to delete any templates? (yes/no): \n"
		read delitans
		if [ $delitans = yes ]
		then
			printf "\nType the names of all instance-templates to be deleted, separated by a space\n"
		read delitname
		gcloud compute instance-templates delete $delitname
		fi

		printf "\nDo you want to create a new instance template (yes) or go with what's already in place (no)? (yes/no): \n"
		read instans
		if [ $instans = yes ]
		then
			printf "Provide a VM Template name: \n"
			read itname
			templatename=$domainid-$itname

			mymachinetype=f1-micro
			myimageproject=centos-cloud
			myimagefamily=centos-7
			myimage=centos-7-v20200811

			#Add a section on gathering VPC and subnet
			printf "\nBelow is a list of all networks (VPC) and subnets you have in us-east4"
			#gcloud compute networks subnets list
			gcloud compute networks subnets list --format=table"(NAME,REGION,NETWORK,RANGE)" --regions=us-east4
			printf "\nEnter network (3rd column) name. Type my-10-vpc for demos: \n"
			read vpcname
			printf "\nEnter subnet (1st column) name. Type my-10-126-1-subnet for demos: \n"
			read mysubnet
			printf "\nWe got these values, if not correct, ctrl-c: \n $vpcname \n $mysubnet \n"
			sleep 5

			printf "\nBy default, our machine type will be $mymachinetype and our Imageproject will be $myimageproject and Imagefamily will be $myimagefamily \n"
			printf "Do you want to change these defaults? (yes/no): \n"
			read imageans
			if [ $imageans = yes ]
			then

				printf "\n\n"
				gcloud compute machine-types list --filter="zone:$myzone" --sort-by=CPUS
				printf "\nPick a machine-type from the list above shown for your current zone: \n"
				read mymachinetype

				gcloud compute images list
				printf "\nFrom above list, pick your image project: \n"
				read myimageproject
				printf "\nAnd what is the image family name: \n"
				read myimagefamily
				printf "\nAnd what is the image name: \n"
				read myimage

				printf "\nOK, so we have, machine type: $mymachinetype and our Imageproject: $myimageproject and Imagefamily: $myimagefamily \n"

			else
				printf "\nok, we'll stick to defaults \n"
			fi

			#Pickup the Service Account we need to associate with the VM instances. For now, we pick the one that has full access.
			printf "\nBelow are the service accounts, for now we are hardcoding test-gcp account"
			gcloud iam service-accounts list

			printf "\nNow creating a VM Template based on all inputs...\n"
			sleep 4
			gcloud beta compute --project=$myproject instance-templates create $templatename --machine-type=$mymachinetype --metadata=startup-script-url=gs://my-isilon-project-bucket-scripts/startup.sh --subnet=projects/$myproject/regions/$myregion/subnetworks/$mysubnet --network-tier=PREMIUM --maintenance-policy=MIGRATE --service-account=test-gcp@my-isilon-project.iam.gserviceaccount.com --scopes=https://www.googleapis.com/auth/cloud-platform --region=$myregion --image=$myimage --image-project=$myimageproject --boot-disk-size=20GB --boot-disk-type=pd-standard --boot-disk-device-name=$templatename --no-shielded-secure-boot --no-shielded-vtpm --no-shielded-integrity-monitoring --reservation-affinity=any


			printf "\n"
			#List current compute instances in all states
			gcloud compute instances list
			printf "Above is a list of all compute instances for your information: \n"
			sleep 5
		else
			printf "\nOK, then nothing to do for setup. Bye. \n"
		fi

	;;
        setupcompute)
		printf "\nOk, will use existing templates to setup your compute as a new Instance Group. \n"
		gcloud compute instance-templates list
		printf "\nFrom above list of templates, which one to use?: \n"
		read currenttemplate
		#Now, create a managed instance group using the above template
		printf "Enter the Managed Instance Group name: \n"
		read migname
		myminame=$domainid-$migname

		printf "\nHow many compute instances do you want to run? \n"
		read mininst
		#printf "\nHow many compute instances do you want at max? \n"
		#read maxinst

		gcloud beta compute --project=$myproject instance-groups managed create $myminame --base-instance-name=$myminame --template=$currenttemplate --size=$mininst --zones=$myzone

		#Not doing the autoscaling for now
		#gcloud beta compute --project $myproject instance-groups managed set-autoscaling $myminame --zone $myzone --cool-down-period "60" --max-num-replicas $maxinst --min-num-replicas $mininst --target-cpu-utilization "0.01" --mode "on"
		printf "\n\nUser $domainid, below are your Compute Instances, please terminate the Managed Instance Group when no longer needed to AVOID COSTS!!! \n"
		gcloud compute instances list
		printf "\n\n\nGoodbye!!\n"

	;;
	*)
		printf "\nInput error try again\n"
		exit 5
esac

printf "end \n\n"

#Below FW rule has to be added one time:
#gcloud compute --project=my-isilon-project firewall-rules create allow-ssh-to-fe-instances --direction=INGRESS --priority=1000 --network=my-10-vpc --action=ALLOW --rules=tcp:22 --source-ranges=0.0.0.0/0 --target-service-accounts=test-gcp@my-isilon-project.iam.gserviceaccount.com

#You'd also have to make sure that the Storage bucket hosting the startup script has at least read access given for the above Service Account

