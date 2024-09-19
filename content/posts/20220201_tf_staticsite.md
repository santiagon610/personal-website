---
title: "I made a thing!"
date: 2022-02-01T00:00:00-04:00
draft: false
hero: /images/posts/20220201_terraform_staticsite.png
description: It's not often that I reconsider living in Pennsylvania. This last storm changed that.
menu:
  sidebar:
    name: "Hosting static websites in AWS"
    identifier: terraform-module-staticsite
    weight: -5
tags:
  - aws
  - cloudfront
  - hugo
  - nginx
  - s3
  - terraform
---

I can't think about a time that I made a thing that I liked so much, that I just released it in the wild. But since I figured that I had been working with this module in a private repository for a while, and it worked well for my purposes, maybe it'll be good enough for random strangers to use. And here we are.

So, a bit of background. A lot of the websites that I maintain on a day-to-day basis are generated using [Hugo](https://gohugo.io), which basically creates a static website with none of the dependencies or vulnerabilities of the popular content management systems. These sites don't need any PHP backend, PostgreSQL databases, or anything else of the sort. They're just web pages, like the good old days.

But like just about any other website, it has to run on a web server. The big player these days is [Nginx](https://nginx.org), and it runs on just about every distribution of Linux. But even on the cheapest tier server on DigitalOcean ($5/month), it's pricier than it could be. We're just storing flat files, after all, right?

Enter [Amazon Web Services](https://aws.amazon.com/) and their [S3 Object Storage](https://aws.amazon.com/s3/). Simply stated, you put your objects in a bucket, and set up a policy so that they can be accessed (or not, depending on your needs.) As long as you set up an appropriate security policy for your bucket, they manage the rest: underlying storage hardware, operating system updates and patches, vulnerabilities, and the like. As someone who has a large environment of web services to maintain on a day-to-day, it's nice to have one less thing to think about.

One of the great features of S3 is [being able to host a static website](https://docs.aws.amazon.com/AmazonS3/latest/userguide/WebsiteHosting.html) in their object storage buckets. But they only support a couple of default hostnames, and there's nothing cute about `http://my-s3-bucket-prod.s3-website.us-east-1.amazonaws.com/`. Not one thing.

This is where [CloudFront](https://aws.amazon.com/cloudfront/) comes into the mix. Aside from its ability to be a cache and global content delivery network, we're going to be using a fraction of the service. Basically, we're putting CloudFront in front of S3 so that we can provide a vanity URL, since `https://www.my-s3-driven-website.com` looks way better than the default S3 URL.

Another nice thing is that we can chain in [Amazon Certificate Manager](https://aws.amazon.com/certificate-manager/) (ACM) to force users to access the website securely, and also create the appropriate DNS records in [Amazon Route 53](https://aws.amazon.com/route53/) so that the world can get to it. This combination, for a low-volume website, listerally costs pennies each month to host and maintain. That's it.

Another nice thing about Route 53 and ACM is that they can work together to do certificate validation, allowing us to use an Infrastructure as Code tool like [Terraform](https://terraform.io) to define everything.

Though I can go into a huge diatribe as to how Terraform works, there are a zillion of them on the Internet, and surely one of them will be better at describing things than I can. There are a couple of quick hitters that you need to know about so that you can use Terraform succesfully:

- **Providers**: these are the plug-ins that allow you to use different cloud providers (e.g. AWS, Azure, DigitalOcean, GCP, etc.)
  - **Resources**: read-write objects that you can create and manipulate (e.g. virtual machines, DNS records, TLS certificates, etc.)
  - **Data Sources**: same as resources, but read-only - useful to use for downstream resources that you define
- **Modules**: these are the plug-ins that allow you to reuse commonly created resources (e.g. this very blog post)

So, simply stated, this module creates a handful of resources:

- **S3 Bucket** in which your website will be stored
- **CloudFront Distribution** to place in front of your website
- **Route 53 Records** to route the public Internet to your static site
- **Amazon Certificate Manager Certificate** to secure the entrypoint
- **Identity Access Manager User** with permissions to deploy to the S3 bucket
- **Lambda@Edge Function** to resolve `index.html` requests

Using this is relatively simple:

```hcl
module "pizza-shop-website" {
  source          = "santiagon610/static-website-cloudfront-acm/aws"
  version         = "0.0.2"
  staticsite_name = "Roxborough Pizza and Subs"
  aws_region      = "us-east-2"
  oai_comment     = "roxpizza-oai"
  domain_list = [
    "www.roxboroughpizzaandsubs.com",
    "roxboroughpizzaandsubs.com"
  ]
  s3_bucket_name = "prod-roxboroughpizza-website"
  tags = {
    environment = "production"
    owner       = "mario@roxboroughpizzaandsubs.com"
  }
  index_document           = "index.html"
  error_document           = "404.html"
  dns_zone_id              = aws_route53_zone.roxboroughpizza.id
  deployer_iam_user        = true
  deployer_iam_user_name   = "prod-roxboroughpizza-deployer"
  cloudfront_index_handler = true
}
```

I like to think that most of the params are pretty straightforward, but here's a quick breakdown of how they work:

- `staticsite_name` is a descriptive name for the website, used for metadata
- `aws_region` will be used for the default region in which calls will be made to the AWS API
- `oai_comment` is a descriptive name for the Origin Access Identity, again used for metadata
- `domain_list` is an array with the fully-qualified domain names to be added in Route 53, ACM, and the like. As of the time of this writing, all of the objects in the domain list have to be members of the same Route 53 hosted zone.
- `s3_bucket_name` is the name of the S3 bucket that will be created to house the website. Much like normal for S3, this must be globally distinctive.
- `tags` are simply used for metadata, and can be any number of key/value pairs.
- `index_document` is the page that will be used for the default index document, which is usually `index.html`.
- `error_document` is the page that will be rendered when a 4xx/5xx error is discovered, defaulted to `404.html`.
- `deployer_iam_user` is used to create an IAM user to deploy to the S3 bucket, if you need one. If you have a different method of using IAM to grant access to the bucket, keep this as false.
- `deployer_iam_user_name` is the name of the user created in IAM, should you choose to enable it above.
- `cloudfront_index_handler` is a boolean that decides whether to resolve `index.html` for subdirectories. CloudFront handles the base of the distribution, but nothing downstream.

This provider is now available [in the Terraform registry](https://registry.terraform.io/modules/santiagon610/static-website-cloudfront-acm/aws/latest), and although it works for me, I may be missing some key functionality.

If you have feedback, feel free to drop me a line. If you find a bug or problem, feel free to call out an issue on GitHub. I'm going to do my best to remain attentive to the module, since I also use it on a regular basis and want to improve it as I go along.

As for now, I think I'm just going to be excited for a couple days and then the novelty of my new Internet stardom (less than 100 invocations served so far) will die out. And I'm good with that.
