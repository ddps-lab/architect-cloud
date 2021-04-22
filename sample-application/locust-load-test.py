from locust import HttpUser, between, task

class MyWebsiteUser(HttpUser):
    wait_time = between(0.5, 1)

    @task
    def load_main(self):
        with open('dog.jpeg', 'rb') as image:
            self.client.post(
                "/predict",
                files={'file':image}
            )
