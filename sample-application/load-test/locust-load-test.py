from locust import HttpUser, between, task

class MyWebsiteUser(HttpUser):
    # simulated user wait between a and b seconds after each task between(a, b)
    wait_time = between(1, 1)

    @task
    def load_main(self):
        with open('dog.jpeg', 'rb') as image:
            self.client.post(
                "/predict",
                files={'file':image}
            )
