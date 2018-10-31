# AWS Technical Assignment
Andrew McSurley

This readme explains the steps I went about to solve this problem and set up all instances correctly configured.  

**Note: the instances must be configured in the order listed in this readme due to dependencies.**

### Table of Contents

* [Terraform Infrastructure](#terraform-infrastructure)
* [Bastion Instance Configuration](#bastion-instance-configuration)
* [DB Instance Configuration](#db-instance-configuration)
* [Web Instance Configuration](#web-instance-configuration)
* [References](#references)

## Terraform Infrastructure

#### Background
In order to stand up infrastructure via Terraform, I used the Terraform 'Getting Started' guide and documentation for each specific resource I needed.  

First, I generated a keypair on my own machine in order to attach to each instance I would provision.  I used the `aws_key_pair` resource that allows you to specify a public key to associate with the AWS key pair that is created.  This resource uses whatever file is named `immuta-key.pub` in the project directory.

Next, I created files `variables.tf` and `keys.autotfvars` that includes values for access keys, route 53 zone ids, the public VPC id, and public subnet ID I knew I would be using across all instances.

After, I specified a `aws_instance` resource for Bastion, Web, and DB respectively.  I selected a t2 micro Amazon Linux for each instance since I knew it had the Docker package in the main repository.  I then assigned necessary attributes.

Security groups are generated with the `aws_security_group` resource.  I defined the given ingress rules to each instance. 
The security groups for Web and DB depend on the Bastion instance and SG as they use the bastion private IP to only allow SSH access from this address.  The DB security group depends on the Web SG for the TCP 6379 rule.  For the ICMP rule I found the CIDR block for the given VPC.

Elastic IPs were created for the Bastion and Web instances to access via the Internet.

Lastly, Route 53 records were made with the `aws_route_53_record` resource for each instance.  These records depend on the instances and their elastic IPs since they use the public/private IPs.  The Bastion and Web instances have records defined in the public zone with their public IPs.  The DB instance has a record in the private zone with its private IP, so it is not internet facing and only the Web application can connect to Redis via the domain db.candidate-172.immuta.io:6379.

#### Execution Steps 

1. [Install Terraform](https://www.terraform.io/downloads.html)
2. Traverse to Immuta directory in your terminal and run: `terraform init`.  This will download the AWS provider plugin and set your terraform working directory.
3. Execute `terraform apply`
4. Answer 'yes' to the prompt in order to provision all Terraform resources.
5. All AWS resources should show created.

## Bastion Instance Configuration

#### Background
In order to SSH to the Bastion instance and allow agent forwarding to the Web and DB instances, I used PuTTY and Pageant in order to add my generated private key using this [link](https://aws.amazon.com/blogs/security/securely-connect-to-linux-instances-running-in-a-private-amazon-vpc/).  I used the same private key I generated in the terraform section and provided with this project.

Next, the Bastion instance requires no further configuration besides adding the admin public key. It is only used to SSH to the other instances.

#### Execution Steps

1. Traverse to Immuta directory in your terminal, ensure you are in the same directory as `immuta-key`.

2. SSH to bastion.candidate-172.immuta.io with PuTTY allowing agent forwarding.

4. Added public admin key to /home/ec2-user/.ssh/authorized_keys file.  Did not use Ansible since Bastion security group only open for port 22 / SSH.

5. Disable password authentication by editing `/etc/ssh/sshd_config`. In this file, create/modify the following settings. If these settings are already in the file, set them to "no" rather than add new lines:

```
ChallengeResponseAuthentication no
PasswordAuthentication no
```

## DB Instance Configuration

The DB instance configuration involves installing Redis from a Dockerfile and runinng the container. The redis server is bound to 0.0.0.0 so it can be accessed from hosts other than itself, and protected mode is turned off.  This allows the Web instance apps to connect to db.candidate-172.immuta.io:6379.  The redis container has been configured to persist data even when the the service is restarted.

#### Execution Steps

1. Traverse to Immuta directory in your terminal, run this command to copy the db directory to the Bastion:

    `scp -i immuta-key -r db ec2-user@bastion.candidate-172.immuta.io:~`

2.  Ensure you are logged in to Bastion instance terminal - see [Bastion Execution Steps](section).

3.  Copy db directory to the DB instance:

    `scp -r db ec2-user@[private IP of db instance]:~`

4. `ssh [private IP of db instance]`

5. `sudo pip install ansible`

    **Note:  In order to execute this command, I allowed HTTP/HTTPS traffic in the DB security group just for this command and the following to set up docker/docker-compose, then removed the rules.**

6. `cd db`

7. `ansible-playbook deploy-db-config.yml`

8.  Exit and reconnect to the DB instance

9. Log into your Docker Hub credentials and ensure docker service is started:
    ```
     sudo service docker start
     docker login
     ```

10.  Start the docker container:

    `ansible-playbook deploy-docker-config.yml`

8. Disable password authentication by editing `/etc/ssh/sshd_config`. In this file, create/modify the following settings. If these settings are already in the file, set them to "no" rather than add new lines:

```
ChallengeResponseAuthentication no
PasswordAuthentication no
```

## Web Instance Configuration:

#### Background

For Docker container configuration, I used the Docker website documentation for both docker and docker-compose. I also used the tutorial referenced to create a basic docker-compose.yml I tweaked to my own needs.  This avoided having to execute each docker command to build and deploy each container.



Each container is created as it’s own service. The vote app and results app are built from their own Dockerfile and source. The nginx container is built from the nginx directory on the Web instance that contains the Dockerfile and nginx.conf.



For Nginxy reverse proxy configuration, I used the Nginx website documentation as well as various tutorials that are referenced. I first started with creating the SSH keys on the machine and setting up the nginx.conf with an HTTP server that redirects to HTTPS.  The HTTPS server defines various SSH parameters for security and the locations for the vote and results application pages.  Application addresses are referenced via an upstream directive and app port, defined in docker-compose file.

#### Execution Steps

1. Traverse to Immuta directory in your terminal, run this command to copy the web directory to the Bastion:

    `scp -i immuta-key -r web ec2-user@bastion.candidate-172.immuta.io:~`

2.  Ensure you are logged in to Bastion instance terminal - see [Bastion Execution Steps](section).

3.  Copy web directory to the Web instance:

    `scp -r web ec2-user@[private IP of web instance]:~`

4. `ssh [private IP of web instance]`

5. `sudo pip install ansible`

6. `cd web`

7. `ansible-playbook deploy-web-config.yml`

8. Run the following command to create SSL self-signed certs, just hit enter on all prompts:

    `sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/nginx-selfsigned.key -out /etc/ssl/certs/nginx-selfsigned.crt -config /home/ec2-user/web/localhost-ssl.conf`

10 . Run the following command to create SSL dhparam file:

    `sudo openssl dhparam 2048 -out /etc/ssl/certs/dhparam.pem`

9. Exit and reconnect to the Web instance

10.  Ensure docker service is started and start the Docker containers:
    ```
    sudo service docker start
    docker-compose up -d
    ```
11. Disable password authentication by editing `/etc/ssh/sshd_config`. In this file, create/modify the following settings. If these settings are already in the file, set them to "no" rather than add new lines:

```
ChallengeResponseAuthentication no
PasswordAuthentication no
```

### Final Notes

The voting application should now be accessible via http://web.candidate-172.immuta.io/vote for the voting app and http://web.candidate-172.immuta.io/results for the results.

## References
- https://www.terraform.io/intro/getting-started/install.html
- https://www.terraform.io/docs/index.html
- https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/hosted-zones-private.html
- https://aws.amazon.com/blogs/security/securely-connect-to-linux-instances-running-in-a-private-amazon-vpc/
- https://docs.docker.com/network
- https://docs.docker.com/compose/install/
- https://docs.docker.com/compose/compose-file
- https://hackernoon.com/running-docker-on-aws-ec2-83a14b780c56
- https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html
- https://docs.aws.amazon.com/AmazonECS/latest/developerguide/docker-basics.html
- https://docs.aws.amazon.com/AmazonECR/latest/userguide/docker-pull-ecr-image.html
- https://docs.aws.amazon.com/AmazonECR/latest/userguide/Registries.html#registry_auth
- https://www.digitalocean.com/community/tutorials/how-to-create-a-self-signed-ssl-certificate-for-nginx-on-centos-7
- https://bjornjohansen.no/optimizing-https-nginx
- https://help.dreamhost.com/hc/en-us/articles/222784068-The-most-important-steps-to-take-to-make-an-nginx-server-more-secure
- https://docs.docker.com/samples/library/nginx/#complex-configuration
- https://redis.io/topics/quickstart
- https://github.com/dockerfile/redis