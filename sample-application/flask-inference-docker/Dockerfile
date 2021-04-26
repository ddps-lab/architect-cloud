FROM amazonlinux:2

RUN \
  yum update -y && \
  yum install git -y && \
  yum install python3-pip -y && \
  pip3 install --upgrade pip

WORKDIR /home
RUN git clone https://github.com/kmu-bigdata/architect-cloud.git
WORKDIR architect-cloud/sample-application/flask-inference/

RUN mkdir -p static/uploads

RUN pip3 install -r requirements.txt

CMD ["python3", "main.py"]
