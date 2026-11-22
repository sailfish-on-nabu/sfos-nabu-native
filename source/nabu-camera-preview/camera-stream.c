#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <poll.h>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <linux/videodev2.h>
#define CALL(x) do { if ((x)<0) {perror(#x); goto fail;} } while(0)
int main(int argc,char **argv){
 if(argc!=5){fprintf(stderr,"node width height fourcc\n");return 2;}
 int fd=open(argv[1],O_RDWR|O_NONBLOCK), started=0, status=1;
 if(fd<0){perror("open");return 1;}
 struct v4l2_capability cap={0};
 CALL(ioctl(fd,VIDIOC_QUERYCAP,&cap));
 printf("driver=%s card=%s caps=%08x\n",cap.driver,cap.card,cap.device_caps);
 struct v4l2_format fmt={.type=V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE};
 fmt.fmt.pix_mp.width=atoi(argv[2]);fmt.fmt.pix_mp.height=atoi(argv[3]);
 fmt.fmt.pix_mp.pixelformat=v4l2_fourcc(argv[4][0],argv[4][1],argv[4][2],argv[4][3]);
 fmt.fmt.pix_mp.field=V4L2_FIELD_NONE;
 CALL(ioctl(fd,VIDIOC_S_FMT,&fmt));
 printf("format=%ux%u fourcc=%c%c%c%c planes=%u stride=%u size=%u\n",
 fmt.fmt.pix_mp.width,fmt.fmt.pix_mp.height,
 fmt.fmt.pix_mp.pixelformat&255,(fmt.fmt.pix_mp.pixelformat>>8)&255,
 (fmt.fmt.pix_mp.pixelformat>>16)&255,(fmt.fmt.pix_mp.pixelformat>>24)&255,
 fmt.fmt.pix_mp.num_planes,fmt.fmt.pix_mp.plane_fmt[0].bytesperline,fmt.fmt.pix_mp.plane_fmt[0].sizeimage);
 struct v4l2_requestbuffers req={.count=4,.type=fmt.type,.memory=V4L2_MEMORY_MMAP};
 CALL(ioctl(fd,VIDIOC_REQBUFS,&req));
 void *mem[4]={0};size_t len[4]={0};
 for(unsigned i=0;i<req.count&&i<4;i++){
  struct v4l2_plane p[VIDEO_MAX_PLANES]={0};
  struct v4l2_buffer b={.index=i,.type=fmt.type,.memory=req.memory,.length=VIDEO_MAX_PLANES,.m.planes=p};
  CALL(ioctl(fd,VIDIOC_QUERYBUF,&b));len[i]=p[0].length;
  mem[i]=mmap(NULL,len[i],PROT_READ|PROT_WRITE,MAP_SHARED,fd,p[0].m.mem_offset);
  if(mem[i]==MAP_FAILED){perror("mmap");goto fail;}
  CALL(ioctl(fd,VIDIOC_QBUF,&b));
 }
 enum v4l2_buf_type type=fmt.type;
 CALL(ioctl(fd,VIDIOC_STREAMON,&type));started=1;
 for(int n=0;n<5;n++){
  struct pollfd pollfd={.fd=fd,.events=POLLIN};
  int r=poll(&pollfd,1,5000);
  if(r<=0){fprintf(stderr,"frame timeout %d errno=%d\n",r,errno);goto fail;}
  struct v4l2_plane p[VIDEO_MAX_PLANES]={0};
  struct v4l2_buffer b={.type=fmt.type,.memory=req.memory,.length=VIDEO_MAX_PLANES,.m.planes=p};
  CALL(ioctl(fd,VIDIOC_DQBUF,&b));
  unsigned char *data=mem[b.index]; uint32_t hash=2166136261; unsigned min=255,max=0;uint64_t sum=0;
  for(unsigned j=0;j<p[0].bytesused;j++){unsigned v=data[j];hash=(hash^v)*16777619;sum+=v;if(v<min)min=v;if(v>max)max=v;}
  printf("frame=%d sequence=%u bytes=%u flags=%x hash=%08x min=%u max=%u mean=%.2f\n",
   n,b.sequence,p[0].bytesused,b.flags,hash,min,max,p[0].bytesused?(double)sum/p[0].bytesused:0);
  CALL(ioctl(fd,VIDIOC_QBUF,&b));
 }
 status=0;
fail:
 if(started){enum v4l2_buf_type t=V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;ioctl(fd,VIDIOC_STREAMOFF,&t);}
 close(fd);return status;
}
